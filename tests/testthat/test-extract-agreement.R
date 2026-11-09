# Agreement between two extraction tables. The reference alphas below were
# worked out once from the two-coder forms of Krippendorff (2011), written out
# independently of the package: with n = 2N pairable values,
#   nominal   1 - (n - 1) * 2 * disagreeing items / (n^2 - sum n_c^2)
#   interval  1 - (n - 1) * sum (a - b)^2 / (n * sum (v - mean v)^2)
#   ratio     1 - (n - 1) * 2 * sum d(a, b) / sum_ij d(v_i, v_j),
#             d = ((a - b) / (a + b))^2
#   ordinal   the same with the rank-sum difference of the margins.

ea_fields <- gr_fields(
  design = gr_field("Study design", type = "enum",
                    values = c("rct", "cohort", "case series")),
  n = gr_field("Number randomised", type = "integer"),
  funded = gr_field("Industry funding declared", type = "boolean")
)

# Forty documents. design: y differs at 3, 10 and 22; x is not reported at 7
# and y at 15, so 5 of 40 disagree (po 0.875). n: 25, 30, ..., 220, not
# reported by both at 12 and by y alone at 27, and off by +10, -5 and +1 at 4,
# 9 and 31. funded: TRUE everywhere, so it is constant.
ea_tables <- function() {
  dx <- rep(c("rct", "cohort", "case series", "rct"), 10)
  dy <- dx; dy[3] <- "cohort"; dy[10] <- "rct"; dy[22] <- "case series"
  dx[7] <- NA; dy[15] <- "Not reported"
  nx <- 20 + 5 * (1:40); ny <- nx
  ny[c(4, 9, 31)] <- ny[c(4, 9, 31)] + c(10, -5, 1)
  nx[12] <- NA; ny[c(12, 27)] <- NA
  docs <- sprintf("doc%02d.pdf", 1:40)
  list(x = data.frame(document = docs, design = dx, n = nx, funded = TRUE,
                      stringsAsFactors = FALSE),
       y = data.frame(document = rev(docs), design = rev(dy), n = rev(ny),
                      funded = "yes", stringsAsFactors = FALSE))
}

test_that("each field gets alpha at its level, with not reported a category or a part", {
  t <- ea_tables()
  ag <- gr_extract_agreement(t$x, t$y, fields = ea_fields, B = 200)
  expect_s3_class(ag, "gr_extract_agreement")
  tab <- ag$table
  expect_identical(tab$field, c("design", "n", "n", "funded"))
  expect_identical(tab$part, c("value", "reported", "value", "value"))
  expect_identical(tab$level, c("nominal", "nominal", "interval", "nominal"))
  expect_identical(tab$n, c(40L, 40L, 38L, 40L))

  # Rows were matched on document, not on position: y is in reverse order.
  d <- tab[tab$field == "design", ]
  expect_equal(d$percent_agreement, 0.875)
  expect_equal(d$alpha, 0.803970223325062, tolerance = 1e-12)
  expect_identical(c(d$not_reported_x, d$not_reported_y), c(1L, 1L))
  expect_true(d$lower <= d$alpha && d$alpha <= d$upper)
  expect_true(is.na(d$note))

  r <- tab[tab$field == "n" & tab$part == "reported", ]
  expect_equal(r$percent_agreement, 0.975)
  expect_equal(r$alpha, 0.658008658008658, tolerance = 1e-12)

  v <- tab[tab$field == "n" & tab$part == "value", ]
  expect_equal(v$percent_agreement, 35 / 38)
  expect_equal(v$alpha, 0.999521617812624, tolerance = 1e-12)

  # The disagreements can be read off the pairs.
  dis <- subset(ag$pairs, field == "design" & x != y)
  expect_identical(sort(dis$document), sprintf("doc%02d.pdf", c(3, 7, 10, 15, 22)))
  expect_identical(dis$x_state[dis$document == "doc07.pdf"], "not reported")
})

test_that("a constant field gets percent agreement and a note, not alpha", {
  t <- ea_tables()
  ag <- gr_extract_agreement(t$x, t$y, fields = ea_fields, B = 0)
  f <- ag$table[ag$table$field == "funded", ]
  expect_identical(f$n, 40L)
  expect_equal(f$percent_agreement, 1)
  expect_true(is.na(f$alpha) && is.na(f$lower) && is.na(f$upper))
  expect_match(f$note, "Every value is the same")
})

test_that("a field compared on fewer than 30 documents gets no alpha", {
  t <- ea_tables()
  x <- t$x[1:12, ]; y <- t$y[t$y$document %in% x$document, ]
  ag <- gr_extract_agreement(x, y, fields = c("design", "n"), B = 0)
  d <- ag$table[ag$table$field == "design", ]
  expect_identical(d$n, 12L)
  # Documents 3, 7 and 10 of the first twelve disagree.
  expect_equal(d$percent_agreement, 9 / 12)
  expect_true(is.na(d$alpha))
  expect_match(d$note, "Only 12 pairable item\\(s\\); alpha needs at least 30")
  v <- ag$table[ag$table$field == "n" & ag$table$part == "value", ]
  expect_identical(v$n, 11L)
  expect_match(v$note, "Only 11 pairable")
})

test_that("declared levels override the type, and ratio and ordinal follow Krippendorff", {
  t <- ea_tables()
  ag <- gr_extract_agreement(t$x, t$y, fields = "n", levels = c(n = "ratio"), B = 0)
  v <- ag$table[ag$table$part == "value", ]
  expect_identical(v$level, "ratio")
  expect_equal(v$alpha, 0.997289937346914, tolerance = 1e-12)

  # An ordinal enum is ordered as declared, not alphabetically.
  sev <- gr_fields(severity = gr_field("Severity", type = "enum",
                                       values = c("low", "mid", "high")))
  ox <- rep(c("low", "mid", "high", "mid", "low"), 8)
  oy <- ox; oy[c(2, 13, 33)] <- c("high", "low", "mid")
  x <- data.frame(document = 1:40, severity = ox)
  y <- data.frame(document = 1:40, severity = oy)
  o <- gr_extract_agreement(x, y, fields = sev, levels = "ordinal", B = 0)$table
  expect_identical(o$part, c("reported", "value"))
  expect_equal(o$alpha[2], 0.885774856792144, tolerance = 1e-12)
  expect_equal(o$percent_agreement[2], 0.925)
  # As nominal, the same labels give the nominal alpha.
  nm <- gr_extract_agreement(x, y, fields = sev, B = 0)$table
  expect_identical(nm$level, "nominal")
  expect_equal(nm$alpha, 0.883308714918759, tolerance = 1e-12)
})

test_that("levels default from the protocol's field types", {
  t <- ea_tables()
  p <- gr_protocol("ea", question = "What was found?", fields = ea_fields)
  ag <- gr_extract_agreement(t$x, t$y, fields = p, B = 0)
  expect_identical(unique(ag$table$level[ag$table$field == "n" & ag$table$part == "value"]),
                   "interval")
  # Without a schema the column types decide.
  ag2 <- gr_extract_agreement(t$x, t$y, B = 0)
  expect_identical(ag2$table$field, c("design", "n", "n", "funded"))
  expect_equal(ag2$table$alpha[3], 0.999521617812624, tolerance = 1e-12)
})

test_that("values are read as the field's type before they are compared", {
  f <- gr_fields(design = gr_field("Design", type = "enum", values = c("rct", "cohort")),
                 arm = "Comparator arm",
                 n = gr_field("Number randomised", type = "integer"))
  x <- data.frame(document = c("a", "b", "c", "d", "e"),
                  design = c("rct", "cohort", "rct", "rct", "cohort"),
                  arm = c("Placebo", "usual care", "None", "N/A", "Placebo."),
                  n = c(120, 85, 40, 60, NA))
  y <- data.frame(document = c("a", "b", "c", "d", "e"),
                  design = c("RCT", "Cohort", "rct", "crossover", "cohort"),
                  arm = c("placebo", "Usual care", "none", "", "\"placebo\""),
                  n = c("120", "1,204", "120 (60 per arm)", "60", "not stated"))
  ag <- gr_extract_agreement(x, y, fields = f, B = 0)
  p <- ag$pairs
  # Case in an enum value is not a disagreement; an undeclared value is unknown.
  expect_identical(p$y_state[p$field == "design"],
                   c("value", "value", "value", "unknown", "value"))
  expect_identical(ag$table$n[ag$table$field == "design"], 4L)
  expect_equal(ag$table$percent_agreement[ag$table$field == "design"], 1)
  # Strings fold case, quote marks and a trailing full stop; "None" is a
  # value in a string field, "N/A" and a blank are not reported.
  arm <- p[p$field == "arm", ]
  expect_identical(arm$x_state, c("value", "value", "value", "not reported", "value"))
  expect_identical(arm$y_state, c("value", "value", "value", "not reported", "value"))
  expect_true(all(arm$x == arm$y))
  # Text numbers are read; one carrying two numbers is unknown, not unreported.
  n <- p[p$field == "n", ]
  expect_identical(n$y, c("120", "1204", NA, "60", "not reported"))
  expect_identical(n$y_state, c("value", "value", "unknown", "value", "not reported"))
  expect_identical(ag$table$unknown[ag$table$field == "n"], c(1L, 1L))
})

test_that("an extraction result's failed, incomplete and duplicate rows are not misread", {
  tab <- data.frame(document = c("a", "b", "c", "d", "e"),
                    design = c("rct", NA, NA, "rct", "rct"),
                    n = c(100L, NA, NA, 50L, 100L),
                    funded = c(TRUE, NA, NA, FALSE, TRUE),
                    status = c("ok", "incomplete", "failed", "ok", "duplicate"),
                    duplicate_of = c(NA, NA, NA, NA, "a"),
                    stringsAsFactors = FALSE)
  ex <- structure(list(table = tab, fields = ea_fields, answers = list()),
                  class = "gr_extraction")
  person <- data.frame(document = c("a", "b", "c", "d", "e", "f"),
                       design = c("rct", "cohort", "cohort", "rct", "rct", "rct"),
                       n = c(100, NA, 30, 50, 100, 10),
                       funded = c("yes", "no", "no", "no", "yes", "no"))
  ag <- gr_extract_agreement(ex, person, B = 0)
  # The schema came from the extraction; "e" duplicates "a" and is dropped.
  expect_identical(unique(ag$table$field), c("design", "n", "funded"))
  expect_identical(ag$unmatched, list(x = character(0), y = c("e", "f")))
  p <- ag$pairs[ag$pairs$field == "design", ]
  # "b" was read in part, so its empty cell is unknown; "c" was not read.
  expect_identical(p$x_state, c("value", "unknown", "unknown", "value"))
  d <- ag$table[ag$table$field == "design", ]
  expect_identical(c(d$n, d$unknown, d$not_reported_x), c(2L, 2L, 0L))
  expect_equal(d$percent_agreement, 1)
  expect_true(any(grepl("repeating another document", ag$notes)))
  expect_true(any(grepl("0 document(s) only in `x` and 2 only in `y`", ag$notes, fixed = TRUE)))
  expect_output(print(ag), "<gr_extract_agreement> 3 field\\(s\\), 4 document\\(s\\) matched")
})

test_that("the bootstrap is seeded and leaves the caller's random state alone", {
  t <- ea_tables()
  set.seed(42); before <- .Random.seed
  a1 <- gr_extract_agreement(t$x, t$y, fields = "design", B = 100, seed = 7)
  expect_identical(.Random.seed, before)
  a2 <- gr_extract_agreement(t$x, t$y, fields = "design", B = 100, seed = 7)
  expect_identical(a1$table, a2$table)
})

test_that("bad settings stop with a reason", {
  t <- ea_tables()
  expect_error(gr_extract_agreement(t$x, t$y, fields = "nope"), class = "gr_bad_setting")
  expect_error(gr_extract_agreement(t$x, t$y, fields = "n", levels = "bogus"),
               class = "gr_bad_setting")
  expect_error(gr_extract_agreement(t$x, t$y, fields = "n", levels = c(m = "ratio")),
               class = "gr_bad_setting")
  expect_error(gr_extract_agreement(t$x, t$y, fields = "n", levels = c("ratio", "nominal")),
               class = "gr_bad_setting")
  expect_error(gr_extract_agreement(t$x, t$y, by = "id"), class = "gr_bad_setting")
  expect_error(gr_extract_agreement(t$x, rbind(t$y, t$y[1, ])), "more than one row",
               class = "gr_bad_setting")
  y <- t$y; y$document <- paste0("other", seq_len(nrow(y)))
  expect_error(gr_extract_agreement(t$x, y), "nothing to compare", class = "gr_bad_setting")
  neg <- t$x; neg$n[1] <- -5
  expect_error(gr_extract_agreement(neg, t$y, fields = "n", levels = "ratio"),
               "below zero", class = "gr_bad_setting")
  expect_error(gr_extract_agreement(t$x, t$y, fields = 3), class = "gr_bad_setting")
})

test_that("a level that does not fit the field's type stops rather than misreading it", {
  ox <- rep(c("low", "mid", "high", "mid", "low"), 8)
  oy <- ox; oy[c(2, 13, 33)] <- c("high", "low", "mid")
  x <- data.frame(document = 1:40, severity = ox)
  y <- data.frame(document = 1:40, severity = oy)
  # Text with no declared order would be ranked alphabetically.
  expect_error(gr_extract_agreement(x, y, levels = "ordinal", B = 0),
               "no declared order", class = "gr_bad_setting")
  expect_error(gr_extract_agreement(x, y, fields = gr_fields(severity = gr_field("Severity")),
                                    levels = "ordinal", B = 0),
               "no declared order", class = "gr_bad_setting")
  # Enum labels and logicals cannot be read as numbers.
  f <- gr_fields(f = gr_field("F", type = "enum", values = c("a", "b")))
  ab <- data.frame(document = 1:40, f = rep(c("a", "b"), 20))
  expect_error(gr_extract_agreement(ab, ab, fields = f, levels = "interval", B = 0),
               "needs numbers", class = "gr_bad_setting")
  lg <- data.frame(document = 1:40, f = rep(c(TRUE, FALSE), 20))
  expect_error(gr_extract_agreement(lg, lg, levels = "ratio", B = 0),
               "needs numbers", class = "gr_bad_setting")
  # Numeric text in a string field is still read at the interval level.
  num <- data.frame(document = 1:40, f = as.character(1:40))
  ok <- gr_extract_agreement(num, num, fields = gr_fields(f = gr_field("F")),
                             levels = "interval", B = 0)$table
  expect_identical(ok$n[ok$part == "value"], 40L)
})

test_that("an extraction's unreadable fields are found when rows match on another column", {
  ex <- structure(list(table = data.frame(document = c("a.pdf", "b.pdf"),
                                          document_id = c("id1", "id2"),
                                          n = c(NA, 10), stringsAsFactors = FALSE),
                       fields = gr_fields(n = gr_field("N", type = "integer")),
                       answers = list(a.pdf = list(notes = list(unknown = "n")))),
                  class = "gr_extraction")
  person <- data.frame(document_id = c("id1", "id2"), n = c(NA, 10))
  p <- gr_extract_agreement(ex, person, by = "document_id", B = 0)$pairs
  expect_identical(p$x_state, c("unknown", "value"))
})

test_that("a blank duplicate_of read back from a CSV is not a duplicate", {
  x <- data.frame(document = c("a.pdf", "b.pdf", "c.pdf", "c2.pdf"),
                  status = c("ok", "ok", "ok", "duplicate"),
                  duplicate_of = c(NA, NA, NA, "c.pdf"), n = c(120, 85, 40, 40),
                  stringsAsFactors = FALSE)
  y <- data.frame(document = c("a.pdf", "b.pdf", "c.pdf"), n = c(120, 85, 41))
  f <- tempfile(fileext = ".csv")
  on.exit(unlink(f), add = TRUE)
  utils::write.csv(x, f, row.names = FALSE, na = "")
  x2 <- utils::read.csv(f, stringsAsFactors = FALSE)
  expect_identical(x2$duplicate_of, c("", "", "", "c.pdf"))
  a <- gr_extract_agreement(x, y, fields = "n", B = 0)
  b <- gr_extract_agreement(x2, y, fields = "n", B = 0)
  # a, b and c compared in both; c2.pdf left out as a duplicate of c.pdf.
  # All three report n (agreement 1) and two of the three values match
  # (120, 85; 40 vs 41), so 2 / 3.
  expect_identical(a$table$n, c(3L, 3L))
  expect_identical(b$table$n, c(3L, 3L))
  expect_identical(b$table$part, c("reported", "value"))
  expect_equal(b$table$percent_agreement, c(1, 2 / 3))
  expect_identical(b$unmatched, list(x = character(0), y = character(0)))
})
