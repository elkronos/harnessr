# test-synthesis-honesty.R: what the claims and the write-up are told about
# each value's check, how claims are ranked and moderators tested, how claims
# are reconciled, how figures are matched to fields, which studies go
# uncited, re-checking an edited text, and contradicting citations.

ns <- asNamespace("harnessr")

# Two documents: one whose quotes verify, one whose quotes do not.
honesty_extraction <- function(env = parent.frame()) {
  d <- withr::local_tempdir(.local_envir = env)
  writeLines("We ran a randomised trial. We enrolled 120 people.", file.path(d, "a.txt"))
  writeLines("This was a cohort study of 250 adults.", file.path(d, "b.txt"))
  fields <- gr_fields(design = "The study design",
                      n = gr_field("Participants", type = "integer"))
  cl <- hr_mock_client(function(messages, params) {
    seen <- paste(vapply(messages, function(m) as.character(m$content), character(1)),
                  collapse = " ")
    if (grepl("enrolled 120", seen, fixed = TRUE)) {
      paste0('{"design":"randomised trial","n":120,',
             '"design__quote":"We ran a randomised trial.",',
             '"n__quote":"We enrolled 120 people."}')
    } else {
      paste0('{"design":"cohort","n":300,"design__quote":"Made up.",',
             '"n__quote":"Three hundred adults took part maybe."}')
    }
  })
  suppressWarnings(gr_extract(d, fields, client = cl))
}

# A client that records every prompt it is sent and answers each kind of
# request with `answer(kind, messages)`.
recording_client <- function(answer) {
  sent <- new.env()
  sent$prompts <- list()
  cl <- hr_mock_client(function(messages, params) {
    kind <- if (is.null(params$schema)) "text" else as.character(params$schema_name)
    sent$prompts[[length(sent$prompts) + 1L]] <- list(kind = kind, messages = messages)
    answer(kind, messages)
  })
  list(client = cl, sent = sent)
}

prompt_text <- function(sent, kind) {
  hit <- Filter(function(p) identical(p$kind, kind), sent$prompts)
  paste(vapply(hit, function(p) paste(vapply(p$messages, function(m) as.character(m$content),
                                             character(1)), collapse = "\n"), character(1)),
        collapse = "\n")
}

one_claim <- function(sup = "[1,2]", con = "[]", moderator = "null") {
  paste0('{"claims":[{"claim":"Trials enrolled people.","kind":"finding","supported_by":', sup,
         ',"contradicted_by":', con, ',"moderator":', moderator, ',"scope":null}]}')
}

# --- P3-03: each value's check and quote reach the claims and the write-up ---

test_that("the claims prompt shows each value's quote and leaves the unverified out", {
  x <- honesty_extraction()
  rc <- recording_client(function(kind, m) one_claim())
  cm <- suppressWarnings(suppressMessages(gr_claims(x, question = "Q?", client = rc$client)))
  p <- prompt_text(rc$sent, "claims")
  expect_match(p, 'n: 120 (verified quote: "We enrolled 120 people.")', fixed = TRUE)
  expect_false(grepl("300", p, fixed = TRUE))
  expect_false(grepl("cohort", p, fixed = TRUE))
  # Study 2 had nothing left to show, so it was not sent, and the claim's
  # citation of it was dropped as naming a study its batch was not shown.
  expect_false(grepl("[study 2]", p, fixed = TRUE))
  expect_identical(cm$claims$n_support, 1L)
  expect_true(any(grepl("not shown", cm$dropped$reason)))
  expect_setequal(cm$unverified$field, c("design", "n"))
  expect_true(all(cm$unverified$study == 2L))
  expect_false(any(cm$unverified$shown))
  expect_setequal(unique(cm$values$status), c("verified", "unverified"))
  expect_match(paste(capture.output(print(cm)), collapse = "\n"),
               "2 unverified value(s) left out of the claims prompt", fixed = TRUE)
})

test_that("unverified = \"include\" shows the unverified values, marked", {
  x <- honesty_extraction()
  rc <- recording_client(function(kind, m) one_claim())
  cm <- suppressWarnings(gr_claims(x, question = "Q?", client = rc$client,
                                   unverified = "include"))
  p <- prompt_text(rc$sent, "claims")
  expect_match(p, paste0('n: 300 (unverified: the quote given, "Three hundred adults took part ',
                         'maybe.", did not verify)'), fixed = TRUE)
  expect_identical(cm$claims$n_support, 2L)
  expect_true(all(cm$unverified$shown))
  expect_error(gr_claims(x, question = "Q?", client = rc$client, unverified = "maybe"))
})

test_that("a bare table is shown as before, with no status and nothing left out", {
  tab <- data.frame(document = c("a.pdf", "b.pdf"), status = "ok", duplicate_of = NA_character_,
                    n_filled = 1L, n_unverified = c(0L, 1L), conflicts = NA_character_,
                    n = c(120L, 300L), stringsAsFactors = FALSE)
  tab$study <- 1:2
  expect_identical(ns$render_studies(tab, values = ns$value_status(tab, tab, "n")),
                   ns$render_studies(tab))
  expect_identical(ns$render_studies(tab)[2], "[study 2]\nn: 300")
  rc <- recording_client(function(kind, m) one_claim())
  cm <- gr_claims(tab[, setdiff(names(tab), "study")], question = "Q?", client = rc$client)
  expect_identical(nrow(cm$unverified), 0L)
  expect_identical(cm$claims$n_support, 2L)
})

test_that("the write-up shows unverified values marked and links each sentence or flags it", {
  x <- honesty_extraction()
  rc <- recording_client(function(kind, m) {
    paste0("Two studies enrolled 120 people [study 1]. Overall the evidence is thin. ",
           "A cohort followed 300 adults [study 2].")
  })
  s <- suppressWarnings(gr_synthesise(x, question = "Q?", outline = c(Findings = "What"),
                                      client = rc$client))
  p <- prompt_text(rc$sent, "text")
  expect_match(p, "n: 300 (unverified: the quote given", fixed = TRUE)
  expect_match(p, 'design: randomised trial (verified quote: "We ran a randomised trial.")',
               fixed = TRUE)
  sl <- s$sentences
  expect_identical(nrow(sl), 3L)
  expect_identical(sl$linked, c(TRUE, FALSE, FALSE))
  expect_identical(sl$flag, c(NA, "cites no study", "cites no verified record"))
  expect_identical(sl$verified[1], "1")
  out <- paste(capture.output(print(s)), collapse = "\n")
  expect_match(out, "2 of 3 sentence(s) not linked to a verified record", fixed = TRUE)
})

test_that("a bare table's verified records come from its counts, or are unknown", {
  used <- data.frame(study = 1:3, n_filled = c(2L, 2L, 0L), n_unverified = c(0L, 2L, 0L))
  expect_identical(ns$study_verified(used), c(`1` = TRUE, `2` = FALSE, `3` = FALSE))
  expect_identical(ns$study_verified(data.frame(study = 1:2)), c(`1` = NA, `2` = NA))
  sl <- ns$sentence_links("## A\n\nOne [study 1]. Two [study 2].", data.frame(study = 1:2),
                          c(`1` = NA, `2` = NA))
  expect_identical(sl$linked, c(NA, NA))
  expect_identical(sl$flag, c(NA_character_, NA_character_))
})

test_that("the audit report lists the unverified values and the unlinked sentences", {
  x <- honesty_extraction()
  rc <- recording_client(function(kind, m) {
    if (identical(kind, "claims")) return(one_claim("[1]"))
    if (identical(kind, "outline")) {
      return(paste0('{"sections":[{"heading":"Findings","brief":"What","claims":[1],',
                    '"rationale":null}]}'))
    }
    "Trials enrolled 120 people [study 1]. The evidence is thin."
  })
  cm <- suppressWarnings(suppressMessages(gr_claims(x, question = "Q?", client = rc$client)))
  o <- suppressWarnings(gr_outline(cm, client = rc$client))
  s <- suppressWarnings(gr_synthesise(x, question = "Q?", outline = o, claims = cm,
                                      client = rc$client))
  f <- withr::local_tempfile(fileext = ".html")
  suppressWarnings(gr_audit_report(f, extraction = x, synthesis = s, open = FALSE))
  html <- paste(readLines(f, warn = FALSE), collapse = "\n")
  expect_match(html, "Values whose quotes did not verify", fixed = TRUE)
  expect_match(html, "left out of the claims prompt, so no claim rests on them", fixed = TRUE)
  expect_match(html, "Sentences and the records they rest on", fixed = TRUE)
  expect_match(html, "1 of 2 sentence(s) are linked", fixed = TRUE)
})

# --- P3-05: direction tallies and their sign test rank the claims ---------

test_that("the sign test gives 5 of 5 as 0.0625, and 5 studies or fewer are low power", {
  expect_equal(ns$sign_test(5L, 5L), 0.0625)
  expect_equal(ns$sign_test(c(1L, 3L, 9L, 0L), c(1L, 6L, 10L, 0L)),
               c(1, 1, stats::binom.test(9, 10)$p.value, NA))
  expect_equal(ns$sign_test_min(c(5L, 6L)), c(0.0625, 0.03125))
  expect_identical(ns$format_sign_p(c(0.0625, 1, NA)), c("0.0625", "1", "NA"))
})

test_that("claims are ranked by certainty, not by how many studies vote", {
  # Claim 1: a 3-to-3 split over six studies. Claim 2: 5 of 5 agreeing.
  # Claim 3: one study.
  cw <- data.frame(claim_id = 1:3, claim = c("Split.", "Agreed.", "Lone."),
                   kind = "finding", moderator = NA_character_, scope = NA_character_,
                   n_support = c(3L, 5L, 1L), n_contradict = c(3L, 0L, 0L),
                   stringsAsFactors = FALSE)
  support <- data.frame(claim_id = c(rep(1L, 6), rep(2L, 5), 3L),
                        study = c(1:6, 1:5, 7L),
                        role = c(rep("supports", 3), rep("contradicts", 3), rep("supports", 6)),
                        stringsAsFactors = FALSE)
  w <- stats::setNames(rep(1, 7), 1:7)
  expect_identical(ns$claim_order(cw, support, w), c(2L, 1L, 3L))
  blocks <- ns$render_claims(cw, support, w, collapse = FALSE, prominence = c(top = 1/3, middle = 1/3))
  expect_identical(attr(blocks, "claim_id"), c(2L, 1L, 3L))
})

test_that("a claim most of its studies contradict ranks last, not first", {
  # Two-sided, 1 of 9 (p = 0.039) ranked above 5 of 5 (p = 0.0625), and
  # 1 of 6 (p = 0.219) above 3 of 3 (p = 0.25).
  none <- data.frame(claim_id = integer(0), study = integer(0))
  cl <- data.frame(claim_id = 1:3, n_support = c(5L, 1L, 1L), n_contradict = c(0L, 5L, 8L))
  expect_identical(ns$claim_order(cl, none, c()), 1:3)
  cl <- data.frame(claim_id = 1:3, n_support = c(3L, 1L, 1L), n_contradict = c(3L, 0L, 0L))
  cl$n_support[1] <- 1L; cl$n_contradict[1] <- 6L
  expect_identical(ns$claim_order(cl, none, c()), c(2L, 3L, 1L))
  cl <- data.frame(claim_id = 1:3, n_support = c(3L, 1L, 2L), n_contradict = c(0L, 6L, 2L))
  sup <- data.frame(claim_id = c(1, 1, 1, 2, 3, 3), study = 1:6)
  expect_identical(ns$claim_order(cl, sup, c()), c(1L, 3L, 2L))
  cl <- data.frame(claim_id = 1:2, n_support = c(1L, 3L), n_contradict = c(5L, 0L))
  expect_identical(ns$claim_order(cl, none, c()), 2:1)
  expect_identical(ns$claim_against(c(1L, 3L, 2L, NA), c(5L, 0L, 2L, 1L)),
                   c(TRUE, FALSE, FALSE, FALSE))
})

test_that("print() gives each claim's tally and sign test, and warns of low power", {
  tab <- data.frame(document = paste0(letters[1:5], ".pdf"), status = "ok",
                    duplicate_of = NA_character_, n_filled = 1L, n_unverified = 0L,
                    conflicts = NA_character_, finding = "better", stringsAsFactors = FALSE)
  cl <- hr_mock_client(function(m, p) one_claim("[1,2,3,4,5]"))
  cm <- gr_claims(tab, question = "Q?", client = cl)
  expect_equal(cm$claims$sign_p, 0.0625)
  expect_true(cm$claims$low_power)
  out <- paste(capture.output(print(cm)), collapse = "\n")
  expect_match(out, "5 of 5 studies in its direction, sign test p = 0.0625 (low power)",
               fixed = TRUE)
  expect_match(out, "Campbell et al. 2020; Boon and Thomson 2021", fixed = TRUE)
})

# --- P3-06: moderators, declared or exploratory, tested ------------------------

moderator_table <- function() {
  data.frame(document = paste0(letters[1:5], ".pdf"), status = "ok",
             duplicate_of = NA_character_, n_filled = 2L, n_unverified = 0L,
             conflicts = NA_character_,
             design = c("trial", "trial", "trial", "survey", "survey"),
             setting = c("urban", "rural", "urban", "rural", "urban"),
             stringsAsFactors = FALSE)
}

test_that("a 1-vs-1 split is exploratory and can show nothing", {
  tab <- moderator_table()[c(1, 4), ]
  rc <- recording_client(function(kind, m) one_claim("[1]", "[2]", '"design"'))
  cm <- gr_claims(tab, question = "Q?", client = rc$client, moderators = "design")
  mt <- cm$moderators
  expect_identical(nrow(mt), 1L)
  expect_true(mt$declared)
  expect_true(mt$exploratory)
  expect_equal(mt$fisher_p, 1)
  expect_equal(mt$min_p, 1)
  expect_identical(cm$claims$moderator_status, "exploratory")
})

test_that("a declared moderator reports Fisher, Holm and the smallest attainable p", {
  tab <- moderator_table()
  # Two claims, each split 3 trials against 2 surveys by design.
  reply <- paste0('{"claims":[',
    '{"claim":"Trials find it.","kind":"finding","supported_by":[1,2,3],',
    '"contradicted_by":[4,5],"moderator":"design","scope":null},',
    '{"claim":"Trials find it again.","kind":"finding","supported_by":[1,2,3],',
    '"contradicted_by":[4,5],"moderator":"design","scope":null}]}')
  rc <- recording_client(function(kind, m) reply)
  cm <- gr_claims(tab, question = "Q?", client = rc$client, moderators = c("design", "setting"))
  mt <- cm$moderators
  expect_identical(nrow(mt), 2L)
  expect_true(all(mt$declared))
  expect_false(any(mt$exploratory))
  # 3 vs 2, split perfectly: 1 / choose(5, 2).
  expect_equal(mt$fisher_p, c(0.1, 0.1))
  expect_equal(mt$min_p, mt$fisher_p)
  expect_equal(mt$holm_p, stats::p.adjust(c(0.1, 0.1), "holm"))
  expect_identical(cm$declared, c("design", "setting"))
  out <- paste(capture.output(print(cm)), collapse = "\n")
  expect_match(out, "design, declared, 3 vs 2 studies, Fisher p = 0.1 (smallest attainable 0.1), Holm p = 0.2",
               fixed = TRUE)
  expect_match(out, "ICEMAN items (Schandelmaier et al. 2020)", fixed = TRUE)
})

test_that("an undeclared moderator is exploratory, has no Holm p, and is marked so to the writer", {
  tab <- moderator_table()
  rc <- recording_client(function(kind, m) one_claim("[1,2,3]", "[4,5]", '"design"'))
  cm <- gr_claims(tab, question = "Q?", client = rc$client)
  expect_true(cm$moderators$exploratory)
  expect_true(is.na(cm$moderators$holm_p))
  blocks <- ns$render_claims(cm$claims, cm$support, stats::setNames(rep(1, 5), 1:5))
  expect_match(blocks, "distinguished by: design (exploratory)", fixed = TRUE)
  expect_warning(gr_claims(tab, question = "Q?", client = rc$client, moderators = "dose"),
                 class = "gr_moderator_unknown")
  expect_error(gr_claims(tab, question = "Q?", client = rc$client, moderators = 1),
               class = "gr_bad_setting")
  html <- paste(ns$audit_claims(NULL, cm), collapse = "\n")
  expect_match(html, "<h3>Moderators</h3>", fixed = TRUE)
  expect_match(html, "Was the moderator specified before the analysis", fixed = TRUE)
})

# --- P3-07: reconciliation keeps direction and population, and is order-free ---

test_that("a reconcile merge keeps claims of opposite direction or other populations apart", {
  rows <- function(texts, sup) {
    out <- data.frame(claim = texts, kind = "finding", moderator = NA_character_,
                      scope = NA_character_, note = NA_character_, stringsAsFactors = FALSE)
    out$.support <- sup
    out$.contradict <- rep(list(integer(0)), length(texts))
    out
  }
  cl <- hr_mock_client(function(m, p) '{"groups":[[1,2,3,4]]}')
  claims <- rows(c("Exercise improves mood in adults.", "Exercise improves mood in children.",
                   "Exercise does not improve mood in adults.", "Exercise improves adult mood."),
                 list(1L, 2L, 3L, 4:5))
  got <- NULL
  expect_warning(got <- suppressMessages(ns$claims_reconcile(claims, "Q?", cl,
                                                             gr_read_spec("stuff"), hr_trace())),
                 class = "gr_claims_kept_apart")
  expect_identical(nrow(got), 3L)
  sup <- lapply(got$.support, sort)
  expect_true(list(c(1L, 4L, 5L)) %in% sup)
  expect_true(list(2L) %in% sup)
  expect_true(list(3L) %in% sup)
  # The adults' merged claim takes the wording two studies support, not the
  # longest one.
  expect_identical(got$claim[vapply(sup, identical, logical(1), c(1L, 4L, 5L))],
                   "Exercise improves adult mood.")
  # A null finding is 0, not the opposite direction; "It works." names no
  # word of effect.
  expect_identical(ns$claim_direction(c("It lowers mortality.", "It does not lower mortality.",
                                        "It works.", "It failed to work.")),
                   c(-1L, 0L, NA, 0L))
  expect_identical(ns$claim_population("Older adults and children"),
                   list(c("children", "older", "adults")))
})

test_that("reconcile keeps null, harmful and opposite findings apart, and merges agreeing ones", {
  parts <- function(...) {
    txt <- c(...)
    cl <- data.frame(claim = txt, kind = "finding", moderator = NA_character_,
                     scope = NA_character_, note = NA_character_, stringsAsFactors = FALSE)
    cl$.support <- as.list(seq_along(txt))
    cl$.contradict <- replicate(length(txt), integer(0), simplify = FALSE)
    length(ns$claim_split_group(cl, seq_along(txt)))
  }
  # Opposite: an effect against none, a benefit against a harm, a rise
  # against a fall, and populations that differ.
  expect_identical(parts("Mindfulness reduces anxiety", "Mindfulness has no effect on anxiety"), 2L)
  expect_identical(parts("The drug benefits patients", "The drug harms patients"), 2L)
  expect_identical(parts("Tutoring raises test scores",
                         "Tutoring was ineffective for test scores"), 2L)
  expect_identical(parts("Tutoring raises test scores", "Tutoring did not raise test scores"), 2L)
  expect_identical(parts("Mindfulness reduces anxiety", "Mindfulness increases anxiety"), 2L)
  expect_identical(parts("Exercise reduces falls", "Exercise does not reduce falls"), 2L)
  expect_identical(parts("Training improves outcomes in schoolchildren",
                         "Training improves outcomes in adults"), 2L)
  # Agreeing: a benefit and a fall of a bad outcome, and two falls, one
  # worded with "dropout".
  expect_identical(parts("Exercise improves depressive symptoms",
                         "Exercise reduces depressive symptoms"), 1L)
  expect_identical(parts("Incentives reduce dropout", "Incentives lower attrition"), 1L)
  expect_identical(ns$claim_direction(c("Exercise improved mood.",
                                        "Exercise was ineffective for mood.",
                                        "Exercise was harmful to mood.",
                                        "Mood was unchanged by exercise.",
                                        "Exercise improved mood, with no adverse events.",
                                        "Exercise not only improves mood but sleep.")),
                   c(1L, 0L, -1L, 0L, 1L, 1L))
  expect_identical(ns$claim_population("Schoolchildren and schoolgirls"),
                   list(c("children", "women")))
})

# A corpus of 24 studies whose claims split by population and by direction,
# drawn in batches of 5 by a mock that writes one claim per population and
# direction in its batch, wording it with the batch's count, and a reconcile
# mock that groups every claim into one, by topic. Shuffling the table must
# leave the claims matched: the same studies, direction and population.
shuffle_corpus <- function() {
  n <- 24L
  data.frame(document = sprintf("doc%02d.pdf", seq_len(n)),
             document_id = sprintf("id%02d", seq_len(n)), status = "ok",
             duplicate_of = NA_character_, n_filled = 2L, n_unverified = 0L,
             conflicts = NA_character_,
             population = rep(c("adults", "children"), length.out = n),
             effect = rep(c("improved", "improved", "no change"), length.out = n),
             stringsAsFactors = FALSE)
}

shuffle_client <- function() {
  hr_mock_client(function(messages, params) {
    txt <- as.character(messages[[length(messages)]]$content)
    if (identical(params$schema_name, "claim_groups")) {
      n <- length(gregexpr("(?m)^[0-9]+\\. ", txt, perl = TRUE)[[1]])
      return(sprintf('{"groups":[[%s]]}', paste(seq_len(n), collapse = ",")))
    }
    blocks <- strsplit(sub("^<studies>\\n", "", sub("\\n</studies>$", "", txt)), "\\n\\n")[[1]]
    field <- function(b, f) sub(sprintf("^(?s).*\\n%s: ([^\\n]+).*$", f), "\\1", b, perl = TRUE)
    ids <- as.integer(sub("^\\[study ([0-9]+)\\].*$", "\\1", blocks))
    eff <- field(blocks, "effect")
    pop <- field(blocks, "population")
    key <- paste(eff, pop)
    claims <- vapply(split(seq_along(ids), key), function(ix) {
      verb <- if (eff[ix[1]] == "improved") "improved" else "did not improve"
      sprintf(paste0('{"claim":"The intervention %s outcomes in %s, in %d studies of this ',
                     'batch.","kind":"finding","supported_by":[%s],"contradicted_by":[],',
                     '"moderator":null,"scope":null}'),
              verb, pop[ix[1]], length(ix), paste(ids[ix], collapse = ","))
    }, character(1))
    sprintf('{"claims":[%s]}', paste(claims, collapse = ","))
  })
}

claim_signatures <- function(cm) {
  docs <- function(id) {
    s <- cm$support$study[cm$support$claim_id == id & cm$support$role == "supports"]
    paste(sort(cm$studies$document[match(s, cm$studies$study)]), collapse = "|")
  }
  vapply(seq_len(nrow(cm$claims)), function(i) {
    paste(ns$claim_direction(cm$claims$claim[i]),
          paste(ns$claim_population(cm$claims$claim[i])[[1]], collapse = "+"),
          docs(cm$claims$claim_id[i]), sep = " / ")
  }, character(1))
}

test_that("shuffling the table leaves at least 90% of claims matched", {
  tab <- shuffle_corpus()
  run <- function(t) suppressWarnings(suppressMessages(
    gr_claims(t, question = "Does it work?", client = shuffle_client(), max_claim_tokens = 600L)))
  base <- run(tab)
  # Four claims: improved and not improved, in adults and in children, each
  # with every study of its kind, though the reconcile reply grouped all.
  expect_identical(nrow(base$claims), 4L)
  sig <- claim_signatures(base)
  for (seed in 1:5) {
    set.seed(seed)
    shuffled <- run(tab[sample(nrow(tab)), , drop = FALSE])
    matched <- mean(sig %in% claim_signatures(shuffled))
    expect_gte(matched, 0.9)
  }
})

# --- P3-08: figures matched to fields, with pool size and chance ----------

figure_table <- function() {
  data.frame(document = sprintf("s%02d.pdf", 1:10), status = "ok", duplicate_of = NA_character_,
             n_filled = 4L, n_unverified = 0L, conflicts = NA_character_,
             n = c(236, 120, 85, 410, 57, 330, 98, 150, 275, 66),
             response_pct = c(41, 53, 63, 38, 47, 55, 29, 71, 44, 61),
             weeks = c(12, 24, 16, 26, 52, 8, 10, 30, 36, 18),
             age = c(34, 45, 51, 67, 72, 39, 58, 43, 62, 49),
             stringsAsFactors = FALSE)
}

test_that("an uncited 63% in a 40-number pool is unbacked; n = 236 linked to its field is backed", {
  cl <- hr_mock_client(function(m, p) {
    paste0("Response reached 63% across the literature. The largest trial had n = 236. ",
           "Response was 63% in one trial [study 3].")
  })
  s <- suppressWarnings(gr_synthesise(figure_table(), question = "Q?",
                                      outline = c(Findings = "What"), client = cl))
  fig <- s$figures
  uncited <- fig[fig$number == "63" & is.na(fig$studies), ]
  expect_false(uncited$backed)
  expect_identical(uncited$pool, 40L)
  # 2 forms (63 and 0.63) among 90 two-digit numbers, 40 times over.
  expect_equal(uncited$chance, 1 - (1 - 2 / 90)^40)
  expect_true(is.na(uncited$field))
  n236 <- fig[fig$number == "236", ]
  expect_true(n236$backed)
  expect_identical(n236$basis, "rows shown")
  expect_identical(n236$field, "n (study 1)")
  cited <- fig[fig$number == "63" & !is.na(fig$studies), ]
  expect_true(cited$backed)
  expect_identical(cited$field, "response_pct (study 3)")
  expect_identical(cited$pool, 4L)
  expect_identical(s$sections$n_unbacked, 1L)
})

test_that("a field named for one figure does not back another in the sentence", {
  cl <- hr_mock_client(function(m, p) {
    "In the largest trial (n = 410), 57 participants dropped out."
  })
  tab <- figure_table()
  s <- suppressWarnings(gr_synthesise(tab, question = "Q?",
                                      outline = c(Findings = "What"), client = cl))
  fig <- s$figures[s$figures$stage == "draft", ]
  expect_true(fig$backed[fig$number == "410"])
  expect_false(fig$backed[fig$number == "57"])
  expect_true(is.na(fig$field[fig$number == "57"]))
})

test_that("the chance of a coincidental match grows with the pool and shrinks with digits", {
  ch <- ns$figure_chance(c("63", "236", "300", "0.45", "45.2"), c(1, 1, 1, 1, 1), 40)
  expect_equal(ch, 1 - (1 - 1 / c(90, 900, 900, 90, 900))^40)
  expect_true(is.na(ns$figure_chance("", 1, 40)))
  expect_true(ns$figure_field_named("The largest trial had n = 236.", "n"))
  expect_false(ns$figure_field_named("Of 236 people, few left.", "n"))
  expect_true(ns$figure_field_named("The sample size was 236.", "sample_size"))
  expect_false(ns$figure_field_named("The sample was 236.", "sample_size"))
  # Named for the figure itself, not anywhere in the sentence.
  s1 <- "In the largest trial (n = 410), 57 participants dropped out."
  expect_true(ns$figure_field_named(s1, "n", "410"))
  expect_false(ns$figure_field_named(s1, "n", "57"))
  expect_true(ns$figure_field_named("The largest trial had n = 1,236.", "n", "1,236"))
  s2 <- "The sample size was 1,236, and 57 people left."
  expect_true(ns$figure_field_named(s2, "sample_size", "1,236"))
  expect_false(ns$figure_field_named(s2, "sample_size", "57"))
})

# --- Uncited studies: a count, never a quota --------------------------------

test_that("$uncited lists the studies the final text cites nowhere, and whether each was shown", {
  tab <- figure_table()[1:4, ]
  cl <- hr_mock_client(function(m, p) "The largest trial had 236 people [study 1]. Another had 120 [study 2].")
  s <- suppressWarnings(gr_synthesise(tab, question = "Q?", outline = c(Findings = "What"),
                                      client = cl))
  expect_identical(s$uncited$study, 3:4)
  expect_true(all(s$uncited$shown))
  expect_identical(s$uncited$document, c("s03.pdf", "s04.pdf"))
  expect_setequal(s$section_studies$study, 1:4)
  out <- paste(capture.output(print(s)), collapse = "\n")
  expect_match(out, "2 of 4 studies cited nowhere in the text, 2 of them shown to a section",
               fixed = TRUE)
  expect_match(out, "a count, not a quota", fixed = TRUE)
  html <- paste(ns$audit_synthesis(s), collapse = "\n")
  expect_match(html, "Studies the text does not cite", fixed = TRUE)
  expect_match(html, "This is a count, not a quota", fixed = TRUE)
})

test_that("a study no section was shown is uncited and not shown", {
  x <- honesty_extraction()
  rc <- recording_client(function(kind, m) {
    if (identical(kind, "claims")) return(one_claim("[1]"))
    if (identical(kind, "outline")) {
      return(paste0('{"sections":[{"heading":"Findings","brief":"What","claims":[1],',
                    '"rationale":null}]}'))
    }
    "Trials enrolled 120 people [study 1]."
  })
  cm <- suppressWarnings(suppressMessages(gr_claims(x, question = "Q?", client = rc$client)))
  o <- suppressWarnings(gr_outline(cm, client = rc$client))
  s <- suppressWarnings(gr_synthesise(x, question = "Q?", outline = o, claims = cm,
                                      client = rc$client))
  expect_identical(s$uncited$study, 2L)
  expect_false(s$uncited$shown)
})

# --- gr_recheck(): an edited text_marked checked and rendered again ---------

test_that("gr_recheck() renders an edited text and checks its citations again", {
  tab <- data.frame(document = c("a.pdf", "b.pdf", "c.pdf"), status = "ok", n_filled = 2L,
                    n_unverified = 0L, citation = c("Smith, 2019", "Lee, 2021", "Ode, 2020"),
                    n = c(120L, 300L, 45L), stringsAsFactors = FALSE)
  cl <- hr_mock_client(function(m, p) "One trial enrolled 120 people [study 1].")
  s <- suppressWarnings(gr_synthesise(tab, question = "Q?", outline = c(Findings = "Size"),
                                      client = cl))
  expect_identical(s$cite_style, "author-year")
  # Unchanged, it renders as gr_synthesise() did.
  same <- gr_recheck(s)
  expect_identical(same$text, s$text)
  expect_identical(same$references, s$references)
  edited <- paste0(s$text_marked, " Another enrolled 300 people [study 2]. ",
                   "A third enrolled 999 [study 9].")
  warned <- tryCatch(gr_recheck(s, edited), gr_recheck_citations = function(w) "warned")
  expect_identical(warned, "warned")
  r <- suppressWarnings(gr_recheck(s, edited))
  expect_identical(r$recheck$unknown, 9L)
  expect_match(r$text, "(Lee, 2021)", fixed = TRUE)
  expect_match(r$text, "[study 9]", fixed = TRUE)
  expect_true(any(grepl("Lee", r$references)))
  expect_identical(r$uncited$study, 3L)
  expect_true("edited" %in% r$figures$stage)
  expect_identical(attr(r$figures, "published"), "edited")
  expect_false(r$figures$backed[r$figures$stage == "edited" & r$figures$number == "999"])
  expect_identical(r$text_marked, edited)
  expect_identical(r$sections, s$sections)
  expect_error(gr_recheck(s, c("a", "b")), class = "gr_bad_synthesis")
  expect_error(gr_recheck(list(), "a"), class = "gr_bad_synthesis")
})

# Three studies: claim 1 (Mood) rests on 1 and 2 and is contradicted by 3;
# claim 2 (Size) rests on study 1. The Mood section is shown 1 to 3, the Size
# section study 1 only.
recheck_mood_size <- function() {
  tab <- data.frame(document = c("a.pdf", "b.pdf", "c.pdf"), status = "ok", n_filled = 2L,
                    n_unverified = 0L, citation = c("Smith, 2019", "Lee, 2021", "Ode, 2020"),
                    finding = c("better", "better", "worse"), n = c(120L, 300L, 45L),
                    stringsAsFactors = FALSE)
  cl <- hr_mock_client(function(m, p) {
    if (identical(p$schema_name, "claim_groups")) return('{"groups":[[1],[2]]}')
    if (!is.null(p$schema) && grepl("claim", p$schema_name) &&
        !grepl("section|outline", p$schema_name)) {
      return(paste0('{"claims":[{"claim":"Exercise improves mood.","kind":"finding",',
                    '"supported_by":[1,2],"contradicted_by":[3],"moderator":null,"scope":null},',
                    '{"claim":"Trials were small.","kind":"finding","supported_by":[1],',
                    '"contradicted_by":[],"moderator":null,"scope":null}]}'))
    }
    if (!is.null(p$schema)) {
      return(paste0('{"sections":[{"heading":"Mood","brief":"Mood","claims":[1],',
                    '"rationale":null},{"heading":"Size","brief":"Size","claims":[2],',
                    '"rationale":null}]}'))
    }
    all <- paste(vapply(m, function(x) as.character(x$content), ""), collapse = " ")
    if (grepl("Size", all)) "One trial enrolled 120 people [study 1]."
    else "Exercise improved mood [study 1] [study 2]."
  })
  cm <- suppressWarnings(suppressMessages(gr_claims(tab, question = "Q?", client = cl)))
  o <- suppressWarnings(gr_outline(cm, client = cl))
  list(tab = tab, cl = cl, cm = cm,
       s = suppressWarnings(gr_synthesise(tab, question = "Q?", outline = o, claims = cm,
                                          client = cl)))
}

test_that("gr_recheck() keeps the reference of a study another heading cites honestly", {
  s <- recheck_mood_size()$s
  expect_identical(sort(s$section_studies$study[s$section_studies$section == "Size"]), 1L)
  # Size now also cites study 2, which it was not shown; Mood still cites it,
  # and was shown it.
  ed <- sub("120 people [study 1].", "120 people [study 1], another 300 [study 2].",
            s$text_marked, fixed = TRUE)
  r <- suppressWarnings(gr_recheck(s, ed))
  expect_identical(r$recheck$unsupplied, 2L)
  expect_match(r$text, "Lee, 2021; Smith, 2019", fixed = TRUE)
  expect_match(r$text, "another 300 [study 2]", fixed = TRUE)
  expect_true(any(grepl("Lee", r$references)))
  expect_identical(r$uncited$study, 3L)
  # Cited nowhere else, it is kept out of the references and listed uncited.
  ed2 <- gsub("[study 1] [study 2].", "[study 1].", ed, fixed = TRUE)
  r2 <- suppressWarnings(gr_recheck(s, ed2))
  expect_false(any(grepl("Lee", r2$references)))
  expect_identical(r2$uncited$study, 2:3)
})

test_that("gr_recheck() says shown is unknown for a synthesis saved without section_studies", {
  s <- recheck_mood_size()$s
  r <- gr_recheck(s, gsub(" [study 2]", "", s$text_marked, fixed = TRUE))
  expect_identical(r$uncited$shown, c(TRUE, TRUE))
  old <- s
  old$section_studies <- NULL
  r <- gr_recheck(old, gsub(" [study 2]", "", old$text_marked, fixed = TRUE))
  expect_identical(r$uncited$study, 2:3)
  expect_identical(r$uncited$shown, c(NA, NA))
})

test_that("gr_recheck() checks figures with the style and bands the write-up used", {
  tab <- data.frame(document = c("a.pdf", "b.pdf"), status = "ok", n_filled = 1L,
                    n_unverified = 0L, n = c(120L, 300L), stringsAsFactors = FALSE)
  cl <- hr_mock_client(function(m, p) {
    "One trial enrolled about 130 people [study 1]. Each part ran to 250 words [study 2]."
  })
  s <- suppressWarnings(gr_synthesise(tab, question = "Q?", outline = c(Findings = "Size"),
                                      client = cl, style = "Keep each part to 250 words.",
                                      figure_bands = c(about = 0.05)))
  expect_identical(s$style, "Keep each part to 250 words.")
  expect_equal(s$figure_bands[["about"]], 0.05)
  r <- suppressWarnings(gr_recheck(s))
  keep <- c("number", "backed", "basis")
  ed <- r$figures[r$figures$stage == "edited", keep]
  dr <- s$figures[s$figures$stage == "draft", keep]
  rownames(ed) <- rownames(dr) <- NULL
  expect_identical(ed, dr)
  expect_false(ed$backed[ed$number == "130"])
  expect_true(ed$backed[ed$number == "250"])
})

test_that("gr_recheck() leaves a marker for a study the heading's section was not shown", {
  x <- honesty_extraction()
  rc <- recording_client(function(kind, m) {
    if (identical(kind, "claims")) return(one_claim("[1]"))
    if (identical(kind, "outline")) {
      return(paste0('{"sections":[{"heading":"Findings","brief":"What","claims":[1],',
                    '"rationale":null}]}'))
    }
    "Trials enrolled 120 people [study 1]."
  })
  cm <- suppressWarnings(suppressMessages(gr_claims(x, question = "Q?", client = rc$client)))
  o <- suppressWarnings(gr_outline(cm, client = rc$client))
  s <- suppressWarnings(gr_synthesise(x, question = "Q?", outline = o, claims = cm,
                                      client = rc$client))
  r <- suppressWarnings(gr_recheck(s, paste0(s$text_marked, " A cohort had 300 [study 2].")))
  expect_identical(r$recheck$unsupplied, 2L)
  expect_identical(r$recheck$unknown, integer(0))
  expect_match(r$text, "[study 2]", fixed = TRUE)
})

# --- A contradicting study cited without a hedge --------------------------

test_that("a sentence citing a contradicting study for its claim, unhedged, is flagged", {
  tab <- data.frame(document = paste0(letters[1:3], ".pdf"), status = "ok", n_filled = 1L,
                    n_unverified = 0L, finding = c("better", "better", "worse"),
                    stringsAsFactors = FALSE)
  rc <- recording_client(function(kind, m) {
    if (identical(kind, "claims")) {
      return(paste0('{"claims":[{"claim":"Exercise improves mood in adults.","kind":"finding",',
                    '"supported_by":[1,2],"contradicted_by":[3],"moderator":null,"scope":null}]}'))
    }
    if (identical(kind, "outline")) {
      return(paste0('{"sections":[{"heading":"Findings","brief":"What","claims":[1],',
                    '"rationale":null}]}'))
    }
    paste0("Exercise improved mood in adults [study 1] [study 2] [study 3]. ",
           "Exercise may improve mood, though one trial disagreed [study 1] [study 3]. ",
           "Exercise did not improve mood in one trial [study 3].")
  })
  cm <- gr_claims(tab, question = "Q?", client = rc$client)
  o <- suppressWarnings(gr_outline(cm, client = rc$client))
  s <- suppressWarnings(gr_synthesise(tab, question = "Q?", outline = o, claims = cm,
                                      client = rc$client))
  cf <- s$contradictions
  expect_identical(nrow(cf), 1L)
  expect_identical(cf$study, 3L)
  expect_identical(cf$claim_id, 1L)
  expect_match(cf$sentence, "^Exercise improved mood in adults")
  out <- paste(capture.output(print(s)), collapse = "\n")
  expect_match(out, "1 sentence(s) cite a study that contradicts the claim they state", fixed = TRUE)
  html <- paste(ns$audit_synthesis(s), collapse = "\n")
  expect_match(html, "Citations of a contradicting study, unhedged", fixed = TRUE)
  # Without claims there is nothing to contradict.
  expect_identical(nrow(ns$contradiction_flags("A [study 1].", NULL)), 0L)
  # A section of the write-up given no claim states none; a heading the
  # write-up did not have is read against every claim.
  txt <- "## Gaps\n\nExercise improved mood in adults [study 1] [study 3]."
  expect_identical(nrow(ns$contradiction_flags(txt, cm, s$claim_sections,
                                               sections = c("Findings", "Gaps"))), 0L)
  expect_identical(nrow(ns$contradiction_flags(txt, cm, s$claim_sections,
                                               sections = "Findings")), 1L)
  # An unrelated negation or decrease in another clause does not hide the
  # claim the sentence states; a clause that negates it is not the claim.
  flags <- function(t) nrow(ns$contradiction_flags(paste0("## Findings\n\n", t), cm,
                                                    s$claim_sections, sections = "Findings"))
  expect_identical(flags("Exercise improved mood in adults, with no adverse events [study 1] [study 3]."), 1L)
  expect_identical(flags("Exercise improved mood in adults and lowered anxiety [study 1] [study 3]."), 1L)
  expect_identical(flags("Exercise did not improve mood in adults [study 1] [study 3]."), 0L)
})
