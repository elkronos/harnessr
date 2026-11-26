# test-core-models-file.R: the built-in models file, hr_load_models() and
# pricing a built-in model with hr_register_model().
#
# fixtures/models/seed-c3a86ee.csv holds .gr_seed_models() as it was at
# c3a86ee, before the built-in models moved to inst/extdata/models.csv. The
# move must change no limit; the prices are dropped on purpose.
#
# helper-prices.R registers test prices for the built-in models. The tests
# here that look at the built-in entries themselves take those away first.

local_builtin_only <- function(env = parent.frame()) {
  local_unpriced(names(harnessr:::hr_state$seed_models), env = env)
}

seed_fixture <- function() {
  utils::read.csv(test_path("fixtures", "models", "seed-c3a86ee.csv"),
                  colClasses = c(id = "character", context_window = "integer",
                                 max_output = "integer", input_usd = "numeric",
                                 output_usd = "numeric", reasoning = "logical",
                                 supports_temperature = "logical", kind = "character",
                                 dimensions = "integer", as_of = "character"),
                  stringsAsFactors = FALSE)
}

write_models <- function(lines) {
  path <- tempfile(fileext = ".csv")
  writeLines(lines, path)
  withr::defer(unlink(path), envir = parent.frame())
  path
}

models_file_error <- function(expr) {
  tryCatch({
    force(expr)
    NULL
  }, hr_bad_models_file = function(e) e)
}

test_that("the built-in registry keeps every limit it had at c3a86ee, and no prices", {
  old <- seed_fixture()
  now <- harnessr:::hr_state$seed_models
  expect_identical(names(now), old$id)
  fields <- c("id", "context_window", "max_output", "reasoning", "supports_temperature",
              "kind", "dimensions", "as_of")
  for (i in seq_len(nrow(old))) {
    e <- now[[old$id[i]]]
    expect_identical(names(e), c("id", "context_window", "max_output", "input_usd",
                                 "output_usd", "reasoning", "supports_temperature", "kind",
                                 "dimensions", "as_of"))
    for (f in fields) {
      expect_identical(e[[f]], old[[f]][i], info = paste(old$id[i], f))
    }
    expect_identical(e$input_usd, NA_real_, info = old$id[i])
    expect_identical(e$output_usd, NA_real_, info = old$id[i])
  }
})

test_that("the built-in registry is read from the shipped file", {
  path <- system.file("extdata", "models.csv", package = "harnessr")
  expect_true(nzchar(path))
  expect_identical(harnessr:::.gr_seed_models(path), harnessr:::hr_state$seed_models)
  header <- readLines(path, n = 1L)
  expect_false(grepl("usd", header))
})

test_that("hr_models() shows the month the built-in limits were checked", {
  local_builtin_only()
  m <- hr_models()
  old <- seed_fixture()
  built_in <- m[m$id %in% old$id, ]
  expect_identical(sort(built_in$id), sort(old$id))
  expect_true(all(built_in$as_of == "2026-08"))
  expect_true(all(is.na(built_in$input_usd_per_1m)))
  expect_true(all(is.na(built_in$output_usd_per_1m)))
})

test_that("a malformed built-in file fails loudly instead of giving an empty registry", {
  seed <- function(path) harnessr:::.gr_seed_models(path)
  good <- readLines(system.file("extdata", "models.csv", package = "harnessr"))
  expect_error(seed(""), class = "hr_bad_models_file")
  expect_error(seed(tempfile(fileext = ".csv")), class = "hr_bad_models_file")
  expect_error(seed(write_models(character(0))), class = "hr_bad_models_file")
  expect_error(seed(write_models(good[1])), "no rows", class = "hr_bad_models_file")

  # A price column is refused: the shipped file carries none.
  priced <- write_models(c(paste0(good[1], ",input_usd"), paste0(good[2], ",4")))
  e <- models_file_error(seed(priced))
  expect_s3_class(e, "hr_bad_models_file")
  expect_identical(e$column, "input_usd")

  # A blank limit names its row and column.
  blank <- good
  blank[3] <- sub("^([^,]*),[0-9]+,", "\\1,,", blank[3])
  e <- models_file_error(seed(write_models(blank)))
  expect_identical(e$row, 2L)
  expect_identical(e$column, "context_window")
  expect_match(conditionMessage(e), "built-in model file")
  expect_match(conditionMessage(e), "reinstall harnessr")

  # A missing comma would shift values into the wrong columns.
  short <- good
  short[4] <- sub(",2026-08$", "", short[4])
  e <- models_file_error(seed(write_models(short)))
  expect_identical(e$row, 3L)

  # A missing column, and an embedding model without its dimensions.
  e <- models_file_error(seed(write_models(sub(",as_of$", "", sub(",2026-08$", "", good)))))
  expect_identical(e$column, "as_of")
  emb <- grep("^text-embedding-3-small,", good)
  nodims <- good
  nodims[emb] <- sub(",1536,", ",,", nodims[emb])
  e <- models_file_error(seed(write_models(nodims)))
  expect_identical(e$row, emb - 1L)
  expect_identical(e$column, "dimensions")
})

test_that("hr_register_model() prices a built-in model without restating its limits", {
  local_builtin_only()
  before <- hr_model_info("gpt-5")
  expect_identical(before$input_usd, NA_real_)
  hr_register_model("gpt-5", input_usd = 1.25, output_usd = 10)
  after <- hr_model_info("gpt-5")
  for (f in c("context_window", "max_output", "reasoning", "supports_temperature", "kind",
              "dimensions")) {
    expect_identical(after[[f]], before[[f]], info = f)
  }
  expect_identical(after$input_usd, 1.25)
  expect_identical(after$output_usd, 10)
  expect_identical(after$source, "registered")
  expect_identical(after$as_of, format(harnessr:::price_today(), "%Y-%m"))
  expect_equal(hr_estimate_cost("gpt-5", 1e6, 1e6), 11.25)

  # gpt-4 lists an output cap equal to its window; keeping it is not an error.
  expect_no_error(hr_register_model("gpt-4", input_usd = 30, output_usd = 60))
  expect_identical(hr_model_info("gpt-4")$max_output, 8192L)

  # An embedding model needs only the input price.
  hr_register_model("text-embedding-3-small", input_usd = 0.02)
  expect_identical(hr_model_info("text-embedding-3-small")$dimensions, 1536L)
  expect_equal(hr_estimate_cost("text-embedding-3-small", 1e6), 0.02)
})

test_that("changing one field of a registered model keeps the rest", {
  local_registries()
  hr_register_model("my-model", context_window = 32000, max_output = 4000,
                     input_usd = 1, output_usd = 2, reasoning = TRUE)
  stamped <- harnessr:::hr_state$models[["my-model"]]
  st <- harnessr:::hr_state
  st$models[["my-model"]]$as_of <- "2025-01"
  hr_register_model("my-model", max_output = 8000)
  e <- harnessr:::hr_state$models[["my-model"]]
  expect_identical(e$max_output, 8000L)
  expect_identical(e$context_window, 32000L)
  expect_true(e$reasoning)
  expect_identical(c(e$input_usd, e$output_usd), c(1, 2))
  # The prices were kept, so their month was too.
  expect_identical(e$as_of, "2025-01")
  # New prices are stamped with the current month.
  hr_register_model("my-model", input_usd = 3, output_usd = 4)
  expect_identical(harnessr:::hr_state$models[["my-model"]]$as_of,
                   format(harnessr:::price_today(), "%Y-%m"))
  expect_identical(stamped$as_of, format(harnessr:::price_today(), "%Y-%m"))
})

test_that("a full registration still takes the defaults it always did", {
  local_builtin_only()
  hr_register_model("gpt-5", context_window = 400000, max_output = 128000)
  e <- hr_model_info("gpt-5")
  expect_false(e$reasoning)
  expect_true(e$supports_temperature)
  expect_identical(e$input_usd, NA_real_)
})

test_that("hr_register_model() needs limits for a model the registry does not have", {
  local_builtin_only()
  expect_error(hr_register_model("no-such-model", input_usd = 1, output_usd = 2),
               "context_window", class = "gr_bad_setting")
  expect_error(hr_register_model("no-such-model", context_window = 1000),
               "max_output", class = "gr_bad_setting")
  expect_null(harnessr:::hr_state$models[["no-such-model"]])
  # Half a price is still refused, and the error names the call.
  e <- tryCatch(hr_register_model("gpt-4o", input_usd = 2.5), gr_bad_setting = function(e) e)
  expect_match(conditionMessage(e), "no `output_usd`")
  expect_identical(as.character(e$call[[1]]), "hr_register_model")
})

test_that("hr_load_models() adds prices to built-in models and keeps their limits", {
  local_builtin_only()
  path <- write_models(c("id,input_usd,output_usd,as_of",
                         "gpt-4o,2.50,10.00,2026-11",
                         "gpt-4o-mini,0.15,0.60,"))
  expect_invisible(ids <- hr_load_models(path))
  expect_identical(ids, c("gpt-4o", "gpt-4o-mini"))
  a <- hr_model_info("gpt-4o")
  expect_identical(a$context_window, 128000L)
  expect_identical(a$max_output, 16384L)
  expect_identical(c(a$input_usd, a$output_usd), c(2.5, 10))
  expect_identical(a$as_of, "2026-11")
  # No as_of in the row: the current month.
  expect_identical(hr_model_info("gpt-4o-mini")$as_of, format(harnessr:::price_today(), "%Y-%m"))
  m <- hr_models()
  expect_identical(m$input_usd_per_1m[m$id == "gpt-4o"], 2.5)
})

test_that("a row of hr_load_models() registers what hr_register_model() would", {
  local_registries()
  path <- write_models(c(
    "id,context_window,max_output,input_usd,output_usd,cached_input_usd,reasoning,supports_temperature,kind,dimensions",
    "my-chat,32000,4000,1,2,0.5,TRUE,FALSE,chat,",
    "my-embed,8000,0,0.1,,,,,embedding,768",
    "my-bare,16000,1000,,,,,,,"))
  hr_load_models(path)
  from_file <- harnessr:::hr_state$models[c("my-chat", "my-embed", "my-bare")]
  hr_register_model("my-chat", 32000, 4000, input_usd = 1, output_usd = 2,
                    cached_input_usd = 0.5, reasoning = TRUE, supports_temperature = FALSE)
  hr_register_model("my-embed", 8000, 0, input_usd = 0.1, kind = "embedding",
                    dimensions = 768)
  hr_register_model("my-bare", 16000, 1000)
  expect_identical(from_file, harnessr:::hr_state$models[c("my-chat", "my-embed", "my-bare")])
})

test_that("hr_load_models() refuses a malformed file, naming the row and column", {
  local_builtin_only()
  before <- harnessr:::hr_state$models
  cases <- list(
    list(c("id,input_usd,output_usd", "gpt-4o,2.5,10", "gpt-4o-mini,two,0.6"), 2L, "input_usd"),
    list(c("id,input_usd,output_usd", "gpt-4o,2.5,10", "gpt-4o,3,12"), 2L, "id"),
    list(c("id,input_usd,output_usd", "gpt-4o,-1,10"), 1L, "input_usd"),
    list(c("id,input_usd,output_usd", "gpt-4o,2.5,"), 1L, "output_usd"),
    list(c("id,input_usd,price", "gpt-4o,2.5,10"), 0L, "price"),
    list(c("model,input_usd,output_usd", "gpt-4o,2.5,10"), 0L, "model"),
    list(c("input_usd,output_usd", "2.5,10"), 0L, "id"),
    list(c("id,input_usd,output_usd,as_of", "gpt-4o,2.5,10,Nov 2026"), 1L, "as_of"),
    list(c("id,reasoning", "gpt-4o,yes"), 1L, "reasoning"),
    list(c("id,kind", "gpt-4o,image"), 1L, "kind"),
    list(c("id,context_window", "gpt-4o,1.5"), 1L, "context_window"),
    list(c("id,input_usd,output_usd", "no-such-model,1,2"), 1L, "context_window"),
    list(c("id,context_window,max_output", "my-model,4000,4000"), 1L, "max_output"),
    list(c("id,input_usd,output_usd", ",1,2"), 1L, "id")
  )
  for (k in cases) {
    e <- models_file_error(hr_load_models(write_models(k[[1]])))
    expect_s3_class(e, "hr_bad_models_file")
    expect_identical(e$row, k[[2]], info = paste(k[[1]], collapse = " | "))
    expect_identical(e$column, k[[3]], info = paste(k[[1]], collapse = " | "))
    expect_match(conditionMessage(e), sprintf("column '%s'", k[[3]]), fixed = TRUE)
  }
  # An extra value on a row, a missing file, and a file with no rows.
  e <- models_file_error(hr_load_models(write_models(c("id,input_usd,output_usd",
                                                       "gpt-4o,2.5,10,4"))))
  expect_identical(e$row, 1L)
  expect_error(hr_load_models(tempfile(fileext = ".csv")), "no such file",
               class = "hr_bad_models_file")
  expect_error(hr_load_models(write_models("id,input_usd,output_usd")), "no rows",
               class = "hr_bad_models_file")
  expect_error(hr_load_models(NULL), class = "hr_bad_models_file")
  # Nothing was registered, not even the rows before the bad one.
  expect_identical(harnessr:::hr_state$models, before)
})

local_today <- function(date, env = parent.frame()) {
  testthat::local_mocked_bindings(price_today = function() as.Date(date), .package = "harnessr",
                                  .env = env)
}

test_that("changing some of a priced model's prices keeps the older month", {
  local_builtin_only()
  local_price_warnings()
  local_today("2026-11-26")
  hr_load_models(write_models(c("id,input_usd,output_usd,as_of", "gpt-4o,2.5,10,2026-01")))
  # Only the cached price: the input and output prices are still from 2026-01.
  hr_register_model("gpt-4o", cached_input_usd = 1.25)
  a <- hr_model_info("gpt-4o")
  expect_identical(c(a$input_usd, a$output_usd, a$cached_input_usd), c(2.5, 10, 1.25))
  expect_identical(a$as_of, "2026-01")
  expect_warning(hr_estimate_cost("gpt-4o", 1e6, 1e6), class = "hr_stale_price")
  # Only the input price: the output price is still from 2026-01.
  hr_register_model("gpt-4o", input_usd = 3)
  expect_identical(hr_model_info("gpt-4o")$as_of, "2026-01")
  # A file row with some prices and a newer month keeps the older one too.
  hr_load_models(write_models(c("id,input_usd,as_of", "gpt-4o,3.5,2026-10")))
  expect_identical(hr_model_info("gpt-4o")$as_of, "2026-01")
  # Input and output alone leave the cached price from 2026-01.
  hr_register_model("gpt-4o", input_usd = 2.5, output_usd = 10)
  expect_identical(hr_model_info("gpt-4o")$as_of, "2026-01")
  # Every price the entry uses takes the new month.
  hr_register_model("gpt-4o", input_usd = 2.5, output_usd = 10, cached_input_usd = 1.25)
  expect_identical(hr_model_info("gpt-4o")$as_of, "2026-11")
  # An embedding model uses only its input price.
  hr_load_models(write_models(c("id,input_usd,as_of", "text-embedding-3-small,0.02,2026-01")))
  hr_register_model("text-embedding-3-small", input_usd = 0.03)
  expect_identical(hr_model_info("text-embedding-3-small")$as_of, "2026-11")
})

test_that("prices set under a moved date are stamped with that date and are not stale", {
  local_registries()
  local_price_warnings()
  local_today("2027-06-01")
  hr_register_model("fresh-m", context_window = 8000, max_output = 1000,
                    input_usd = 1, output_usd = 2)
  expect_identical(hr_model_info("fresh-m")$as_of, "2027-06")
  expect_no_warning(hr_estimate_cost("fresh-m", 1e6, 1e6), class = "hr_stale_price")
  hr_load_models(write_models(c("id,input_usd,output_usd", "fresh-m,1,2")))
  expect_identical(hr_model_info("fresh-m")$as_of, "2027-06")
})

test_that("hr_load_models() refuses a month after the current one", {
  local_builtin_only()
  local_today("2026-11-26")
  for (month in c("2026-12", "2099-01")) {
    e <- models_file_error(hr_load_models(write_models(
      c("id,input_usd,output_usd,as_of", paste0("gpt-4o,2.5,10,", month)))))
    expect_s3_class(e, "hr_bad_models_file")
    expect_identical(e$row, 1L)
    expect_identical(e$column, "as_of")
    expect_match(conditionMessage(e), "after the current month", fixed = TRUE)
  }
  expect_identical(hr_model_info("gpt-4o")$input_usd, NA_real_)
  hr_load_models(write_models(c("id,input_usd,output_usd,as_of", "gpt-4o,2.5,10,2026-11")))
  expect_identical(hr_model_info("gpt-4o")$as_of, "2026-11")
})

test_that("setting the prices of an alias names the model to set them on", {
  local_builtin_only()
  expect_true(hr_model_info("chatgpt-4o-latest")$certain)
  expect_error(hr_register_model("chatgpt-4o-latest", input_usd = 5, output_usd = 15),
               "'chatgpt-4o-latest' is an alias of 'gpt-4o'; set the prices on 'gpt-4o'",
               fixed = TRUE, class = "gr_bad_setting")
  e <- models_file_error(hr_load_models(write_models(
    c("id,input_usd,output_usd", "chatgpt-4o-latest,5,15"))))
  expect_identical(e$row, 1L)
  expect_identical(e$column, "id")
  expect_match(conditionMessage(e), "alias of 'gpt-4o'", fixed = TRUE)
  expect_null(harnessr:::hr_state$models[["chatgpt-4o-latest"]])
  # Pricing the target prices the alias.
  hr_register_model("gpt-4o", input_usd = 5, output_usd = 15)
  expect_identical(hr_model_info("chatgpt-4o-latest")$input_usd, 5)
})
