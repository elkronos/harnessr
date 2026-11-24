# test-stage-upgrade.R: gr_upgrade_stage() fills the fields a stage object
# saved by an earlier version lacks, and the readers that used to guard each
# field give the same output for such an object as for the saved fixture.
#
# The "older" objects here are the fixtures in fixtures/stages/ with the
# fields added since taken out, as a file saved before them would be.

upgrade_fixture <- function(name) readRDS(test_path("fixtures", "stages", paste0(name, ".rds")))

strip <- function(x, fields) {
  for (f in fields) x[[f]] <- NULL
  x
}

old_claims <- function() strip(upgrade_fixture("claims"), c("lost", "unmerged", "hidden"))

old_synthesis <- function() {
  x <- strip(upgrade_fixture("synthesis"), c("unrendered", "cite_style", "bib_columns"))
  for (f in c("n_unsupplied", "n_unparsed", "n_truncated", "n_unbacked", "lost_batches",
              "capped_batches")) x$sections[[f]] <- NULL
  x$claims <- strip(x$claims, c("lost", "unmerged", "hidden"))
  x
}

hand_screening <- function() {
  tab <- data.frame(document = paste0("d", 1:8, ".pdf"),
                    decision = c("include", "include", "unclear", "exclude",
                                 "exclude", "exclude", "include", "exclude"),
                    stringsAsFactors = FALSE)
  structure(list(table = tab), class = "gr_screening")
}

hand_calibration <- function() {
  ref <- data.frame(document = paste0("d", 1:8, ".pdf"),
                    human_decision = c("include", "exclude", "include", "exclude",
                                       "exclude", "include", "include", "exclude"),
                    stringsAsFactors = FALSE)
  quiet(gr_calibrate(hand_screening(), ref))
}

report_lines <- function(...) {
  path <- tempfile(fileext = ".html")
  on.exit(unlink(path), add = TRUE)
  quiet(gr_audit_report(path, ..., open = FALSE))
  readLines(path, warn = FALSE)
}

test_that("an object made by this version comes back unchanged", {
  for (nm in c("screening", "extraction", "claims", "gaps", "outline", "synthesis")) {
    x <- upgrade_fixture(nm)
    expect_identical(gr_upgrade_stage(x), x, info = nm)
  }
  cal <- hand_calibration()
  expect_identical(gr_upgrade_stage(cal), cal)
})

test_that("hand-built and minimal objects pass through without an error", {
  scr <- hand_screening()
  expect_identical(gr_upgrade_stage(scr), scr)
  ext <- structure(list(table = data.frame(document = "a.pdf")), class = "gr_extraction")
  expect_identical(gr_upgrade_stage(ext), ext)
  for (cls in c("gr_claims", "gr_synthesis", "gr_calibration")) {
    x <- structure(list(), class = cls)
    expect_no_error(y <- gr_upgrade_stage(x))
    expect_identical(class(y), cls, info = cls)
  }
  expect_identical(gr_upgrade_stage(NULL), NULL)
  expect_identical(gr_upgrade_stage("Findings"), "Findings")
  html <- report_lines(screening = scr)
  expect_true(length(html) > 0L)
})

test_that("an older claims table gets its defaults", {
  up <- gr_upgrade_stage(old_claims())
  expect_identical(up$lost, integer(0))
  expect_false(up$unmerged)
  expect_identical(up$hidden, unlist(bib_columns(up$studies), use.names = FALSE))
  # The table itself is left as saved, `sign_p` column and all.
  expect_identical(up$claims, old_claims()$claims)
})

test_that("the claims readers give the same output for an older claims table", {
  cm <- upgrade_fixture("claims")
  old <- old_claims()
  out <- capture.output(res <- print(old))
  expect_identical(res, old)
  expect_identical(out, capture.output(print(cm)))
  expect_identical(gr_gaps(old), gr_gaps(cm))
  syn <- function(claims) {
    quiet(gr_synthesise(upgrade_fixture("extraction"), protocol = golden_protocol(),
                        outline = upgrade_fixture("outline"), claims = claims,
                        client = gr_mock_client(golden_reply)))
  }
  expect_identical(syn(old)$text, syn(cm)$text)
  # gr_synthesise() keeps the claims table it read, filled.
  expect_identical(syn(old)$claims, gr_upgrade_stage(old))
  common <- list(screening = upgrade_fixture("screening"),
                 extraction = upgrade_fixture("extraction"),
                 synthesis = upgrade_fixture("synthesis"), protocol = golden_protocol())
  expect_identical(do.call(report_lines, c(common, list(claims = old))),
                   do.call(report_lines, c(common, list(claims = cm))))
})

test_that("gr_gaps() under a narrower `bib` keeps an older table's hidden columns", {
  # With the default `bib` the conventional columns come back anyway, so only
  # a `bib` that withholds less shows whether `hidden` was filled.
  tab <- data.frame(document = paste0(letters[1:4], ".pdf"), status = "ok",
                    duplicate_of = NA_character_, n_filled = 1L, n_unverified = 0L,
                    conflicts = NA_character_, design = c("cohort", "cohort", "rct", "rct"),
                    authors = "Smith, J.; Okafor, A.", stringsAsFactors = FALSE)
  cl <- gr_mock_client(function(messages, params) paste0(
    '{"claims":[{"claim":"One cohort found it.","kind":"finding","supported_by":[1],',
    '"contradicted_by":[],"moderator":null,"scope":"one study"}]}'))
  cm <- quiet(gr_claims(tab, question = "Q?", client = cl))
  expect_true("authors" %in% cm$hidden)
  old <- strip(cm, c("lost", "unmerged", "hidden"))
  up <- gr_upgrade_stage(old)
  expect_true("authors" %in% up$hidden)
  expect_identical(gr_gaps(old, bib = c(authors = NA)), gr_gaps(cm, bib = c(authors = NA)))
  expect_false("authors" %in% gr_gaps(old, bib = c(authors = NA))$dimension)
})

test_that("a claims table that lost studies still says so after the upgrade", {
  cm <- upgrade_fixture("claims")
  cm$lost <- 2L
  cm$unmerged <- TRUE
  expect_identical(gr_upgrade_stage(cm), cm)
  out <- capture.output(print(cm))
  expect_true(any(grepl("PARTIAL: 1 of", out, fixed = TRUE)))
  expect_true(any(grepl("UNMERGED", out, fixed = TRUE)))
})

test_that("the synthesis readers give the same output for an older synthesis", {
  syn <- upgrade_fixture("synthesis")
  old <- old_synthesis()
  up <- gr_upgrade_stage(old)
  expect_identical(up$unrendered, integer(0))
  expect_identical(up$cite_style, "marker")
  expect_identical(up$sections$lost_batches, integer(nrow(up$sections)))
  expect_identical(up$claims$lost, integer(0))
  expect_false(up$claims$unmerged)
  expect_false(is.null(up$bib_columns))
  expect_identical(up$bib_columns, bib_columns(up$studies))
  out <- capture.output(res <- print(old))
  expect_identical(res, old)
  expect_identical(out, capture.output(print(syn)))
  common <- list(screening = upgrade_fixture("screening"),
                 extraction = upgrade_fixture("extraction"), protocol = golden_protocol())
  expect_identical(do.call(report_lines, c(common, list(synthesis = old))),
                   do.call(report_lines, c(common, list(synthesis = syn))))
  fields <- c("text", "text_marked", "references", "figures", "uncited", "contradictions",
              "recheck", "sentences")
  expect_identical(quiet(gr_recheck(old))[fields], quiet(gr_recheck(syn))[fields])
  re <- quiet(gr_recheck(old))
  # gr_recheck() returns the filled object, nested claims table included.
  expect_identical(re$claims$lost, integer(0))
  expect_false(re$claims$unmerged)
  expect_false(is.null(re$bib_columns))
})

test_that("an older calibration's report keeps the count sentence", {
  cal <- hand_calibration()
  expect_false(cal$adequate)
  old <- strip(cal, "adequacy")
  up <- gr_upgrade_stage(old)
  expect_identical(up$adequacy$rule, "positives")
  expect_match(up$adequacy$note, "eligible record(s) in the sample, below the 10", fixed = TRUE)
  html <- paste(report_lines(screening = hand_screening(), calibration = old), collapse = "\n")
  expect_match(html, "<p class='flag'>Only 4 eligible record(s) in the sample, below the 10 this",
               fixed = TRUE)
  # A calibration with its own note shows the note, as before.
  html <- paste(report_lines(screening = hand_screening(), calibration = cal), collapse = "\n")
  expect_match(html, cal$adequacy$note, fixed = TRUE)
})
