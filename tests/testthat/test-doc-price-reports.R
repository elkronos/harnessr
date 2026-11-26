# test-doc-price-reports.R: the document layer's cost reports say where their
# prices came from, as the core's do (test-core-price-reports.R): the
# comparison table, the audit report's cost table and the folder survey.

dpr_doc <- function(n = 6L) {
  paste(sprintf("Paragraph %d. Revenue was 45.2 million dollars in year %d, and costs were flat.",
                seq_len(n), 2000L + seq_len(n)), collapse = "\n\n")
}

dpr_recipes <- function() {
  seg <- list(method = "paragraph", max_tokens = 40, overlap_tokens = 0)
  list(stuffed = gr_recipe("stuffed", segment = seg, read = list(reader = "stuff")),
       mapped = gr_recipe("mapped", segment = seg, read = list(reader = "map_reduce")))
}

# Register `id` with prices from the month `as_of`.
dpr_price <- function(id, as_of) {
  f <- tempfile(fileext = ".csv")
  on.exit(unlink(f), add = TRUE)
  writeLines(c("id,context_window,max_output,input_usd,output_usd,as_of",
               sprintf("%s,8000,500,2,8,%s", id, as_of)), f)
  hr_load_models(f)
}

test_that("gr_compare() gives each recipe's price columns, last", {
  local_registries()
  local_mocked_bindings(price_today = function() as.Date("2026-12-01"))
  dpr_price("dpr-priced", "2026-11")
  cl <- hr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
  cmp <- quiet(gr_compare(dpr_doc(), "What was revenue?", dpr_recipes(), client = cl,
                          model = "dpr-priced", correct = "45.2 million"))
  s <- cmp$summary
  expect_identical(utils::tail(names(s), 3L), c("priced", "as_of", "certain"))
  # The columns there before keep their order.
  expect_identical(match(c("usd", "usd_estimated", "correct", "usd_per_correct"), names(s)),
                   sort(match(c("usd", "usd_estimated", "correct", "usd_per_correct"),
                              names(s))))
  expect_true(all(s$priced))
  expect_true(all(s$as_of == "2026-11"))
  expect_true(all(s$certain))

  hr_register_model("dpr-unpriced", context_window = 8000, max_output = 500)
  un <- quiet(gr_compare(dpr_doc(), "What was revenue?", dpr_recipes()[1], client = cl,
                         model = "dpr-unpriced"))
  expect_false(un$summary$priced)
  expect_true(is.na(un$summary$as_of))
  expect_true(is.na(un$summary$usd))
})

test_that("the audit report's cost table names the month of the prices, or the missing price", {
  local_registries()
  local_mocked_bindings(price_today = function() as.Date("2026-12-01"))
  dpr_price("dpr-priced", "2026-11")
  hr_register_model("dpr-unpriced", context_window = 8000, max_output = 500)
  cl <- hr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
  a <- quiet(answer_document(dpr_doc(), "What was revenue?", "fast", client = cl,
                             model = "dpr-priced"))
  html <- paste(harnessr:::audit_cost(reading = a), collapse = "\n")
  expect_match(html, "<th>prices</th>", fixed = TRUE)
  expect_match(html, "as of 2026-11", fixed = TRUE)
  b <- quiet(answer_document(dpr_doc(), "What was revenue?", "fast", client = cl,
                             model = "dpr-unpriced"))
  html <- paste(harnessr:::audit_cost(reading = b), collapse = "\n")
  expect_match(html, "no price set for dpr-unpriced (set one with hr_register_model()",
               fixed = TRUE)
})

test_that("gr_inventory() says where its cost floor's prices came from", {
  local_registries()
  local_mocked_bindings(price_today = function() as.Date("2026-12-01"))
  dpr_price("dpr-priced", "2026-11")
  d <- withr::local_tempdir()
  writeLines(dpr_doc(), file.path(d, "a.txt"))
  inv <- gr_inventory(d, model = "dpr-priced")
  expect_true(inv$totals$priced)
  expect_identical(inv$totals$as_of, "2026-11")
  expect_true(inv$totals$certain)
  expect_gt(inv$totals$cost_floor_usd, 0)
  expect_true(any(grepl("(dpr-priced, one call per document), prices as of 2026-11",
                        capture.output(print(inv)), fixed = TRUE)))

  # An empty source has the same totals fields, for the same model.
  empty <- gr_inventory(withr::local_tempdir(), model = "dpr-priced")
  expect_identical(names(empty$totals), names(inv$totals))
  expect_true(empty$totals$priced)
  expect_identical(empty$totals$as_of, "2026-11")
  expect_true(empty$totals$certain)
  expect_true(is.na(empty$totals$cost_floor_usd))

  hr_register_model("dpr-unpriced", context_window = 8000, max_output = 500)
  un <- gr_inventory(d, model = "dpr-unpriced")
  expect_false(un$totals$priced)
  expect_true(is.na(un$totals$cost_floor_usd))
  expect_true(any(grepl(paste0("cost floor: unknown: no price set for dpr-unpriced (set one ",
                               "with hr_register_model() or hr_load_models())"),
                        capture.output(print(un)), fixed = TRUE)))
})

test_that("gr_read_many() gives each document's price columns after `warnings`", {
  local_registries()
  local_clean_cache()
  local_mocked_bindings(price_today = function() as.Date("2026-12-01"))
  dpr_price("dpr-priced", "2026-11")
  hr_register_model("dpr-unpriced", context_window = 8000, max_output = 500)
  cl <- hr_mock_client(function(m, p) "Revenue was 45.2 million dollars.")
  docs <- c(a = dpr_doc(), b = dpr_doc(4L))
  out <- quiet(gr_read_many(docs, "What was revenue?", "fast", client = cl,
                            model = "dpr-priced"))
  s <- out$summary
  at <- match("warnings", names(s))
  expect_identical(names(s)[at + 0:3], c("warnings", "priced", "as_of", "certain"))
  expect_true(all(s$priced))
  expect_true(all(s$as_of == "2026-11"))
  expect_true(all(s$certain))
  html <- paste(harnessr:::audit_corpus(out), collapse = "\n")
  expect_match(html, "<th>prices</th>", fixed = TRUE)
  expect_match(html, "as of 2026-11", fixed = TRUE)

  un <- quiet(gr_read_many(docs, "What was revenue?", "fast", client = cl,
                           model = "dpr-unpriced"))
  expect_false(any(un$summary$priced))
  expect_true(all(is.na(un$summary$as_of)))
  expect_true(all(is.na(un$summary$cost_usd)))
  expect_match(paste(harnessr:::audit_corpus(un), collapse = "\n"), "no price set", fixed = TRUE)

  # A row restored from a store written before the columns gets them, unknown,
  # and binds with a row read now.
  store <- withr::local_tempdir()
  quiet(gr_read_many(docs["a"], "What was revenue?", "fast", client = cl,
                     model = "dpr-priced", store = store))
  for (f in list.files(store, pattern = "[.]rds$", full.names = TRUE, recursive = TRUE)) {
    e <- readRDS(f)
    e$row <- e$row[setdiff(names(e$row), c("priced", "as_of", "certain"))]
    saveRDS(e, f)
  }
  mixed <- quiet(gr_read_many(docs, "What was revenue?", "fast", client = cl,
                              model = "dpr-priced", store = store))
  ms <- mixed$summary
  expect_identical(ms$status, c("restored", "ok"))
  expect_identical(names(ms), names(s))
  expect_identical(ms$priced, c(NA, TRUE))
  expect_identical(ms$as_of, c(NA, "2026-11"))
})
