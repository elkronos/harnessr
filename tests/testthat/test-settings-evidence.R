# test-settings-evidence.R: every setting added from now on says what evidence
# backs its default.
#
# gr_settings_table() has a `status` column: "untested", "cited" or
# "measured". The schemas of the specs and the tuning options must give one
# (test-settings.R), but nothing made a new function argument or option give
# one. The settings listed below had no status when this test was written; they
# are let through as they are, and the list may only shrink. Any other row
# must carry a status. To add a setting, declare its evidence (for a function
# argument, an entry in .gr_stage_evidence in R/doc-settings-table.R); never
# add it here.

settings_unrated_frozen <- c(
  "read | gr_read_many() | recipe",
  "read | gr_read_many() | store",
  "read | gr_read_many() | on_error",
  "read | gr_read_many() | max_total_usd",
  "read | gr_read_many() | max_total_calls",
  "read | gr_read_many() | keep_answers",
  "read | gr_read_many() | recursive",
  "screen | gr_screen() | recipe",
  "screen | gr_screen() | store",
  "screen | gr_screen() | on_error",
  "screen | gr_screen() | max_total_usd",
  "screen | gr_screen() | max_total_calls",
  "screen | gr_screen() | keep_answers",
  "screen | gr_screen() | recursive",
  "screen | gr_reference() | n",
  "screen | gr_reference() | of",
  "screen | gr_reference() | seed",
  "screen | gr_reference() | blind",
  "screen | gr_reference() | frame",
  "screen | gr_reference() | reviewers",
  "screen | gr_calibrate() | positive",
  "screen | gr_calibrate() | min_positives",
  "screen | gr_calibrate() | of",
  "screen | gr_calibrate() | max_lost",
  "screen | gr_screen_sample_size() | prevalence",
  "screen | gr_screen_sample_size() | frame",
  "screen | gr_screen_sample_size() | max_lost",
  "screen | gr_screen_sample_size() | frame_n",
  "screen | gr_stop_test() | target",
  "screen | gr_stop_test() | alpha",
  "screen | gr_stop_test() | n_total",
  "extract | gr_extract() | recipe",
  "extract | gr_extract() | store",
  "extract | gr_extract() | on_error",
  "extract | gr_extract() | max_total_usd",
  "extract | gr_extract() | max_total_calls",
  "extract | gr_extract() | keep_answers",
  "extract | gr_extract() | recursive",
  "synthesise | gr_claims() | model",
  "synthesise | gr_claims() | temperature",
  "synthesise | gr_claims() | max_claim_tokens",
  "synthesise | gr_claims() | include_unclear",
  "synthesise | gr_claims() | effort",
  "synthesise | gr_outline() | model",
  "synthesise | gr_outline() | temperature",
  "synthesise | gr_outline() | max_sections",
  "synthesise | gr_outline() | closing",
  "synthesise | gr_outline() | max_outline_tokens",
  "synthesise | gr_outline() | effort",
  "synthesise | gr_outline() | alternatives",
  "synthesise | gr_gaps() | max_cells",
  "synthesise | gr_gaps() | min_reported",
  "synthesise | gr_synthesise() | model",
  "synthesise | gr_synthesise() | max_section_tokens",
  "synthesise | gr_synthesise() | temperature",
  "synthesise | gr_synthesise() | include_unclear",
  "synthesise | gr_synthesise() | cite_style",
  "synthesise | gr_synthesise() | style",
  "synthesise | gr_synthesise() | references",
  "synthesise | gr_synthesise() | effort",
  "synthesise | gr_synthesise() | study_weights",
  "evaluate | hr_benchmark() | runs",
  "evaluate | hr_benchmark() | scorer",
  "evaluate | hr_benchmark() | split",
  "evaluate | hr_benchmark() | governor",
  "evaluate | hr_benchmark() | seed",
  "evaluate | hr_report() | contrasts",
  "evaluate | hr_report() | B",
  "evaluate | hr_report() | conf",
  "evaluate | hr_report() | k",
  "evaluate | hr_report() | seed",
  "evaluate | hr_report() | method",
  "evaluate | hr_report() | confirmatory",
  "evaluate | hr_report() | auto_bootstrap_at",
  "evaluate | hr_report() | min_runs",
  "evaluate | hr_judge() | mode",
  "evaluate | hr_judge() | model",
  "evaluate | hr_judge() | orders",
  "evaluate | hr_judge() | governor",
  "evaluate | hr_judge() | draw_index",
  "evaluate | gr_compare() | recipes",
  "evaluate | gr_compare() | allow_duplicates",
  "evaluate | gr_compare() | on_error",
  "options | hr_options() | verbose",
  "options | hr_options() | tokenizer",
  "options | hr_options() | model",
  "options | hr_options() | embedding_model",
  "options | hr_options() | api_base",
  "options | hr_options() | api_headers",
  "options | hr_options() | api",
  "options | hr_options() | cache_documents",
  "options | hr_options() | cache_embeddings",
  "options | hr_options() | cache_dir",
  "options | hr_options() | embedder",
  "options | hr_options() | parallel",
  "options | hr_options() | max_cost_usd",
  "options | hr_options() | max_calls",
  "options | hr_options() | max_tokens_total",
  "options | hr_options() | max_output_tokens",
  "options | hr_options() | allowed_models",
  "options | hr_options() | allow_unpriced",
  "options | hr_options() | unknown_model_action",
  "options | hr_options() | actor"
)

settings_key <- function(s) paste(s$stage, s$where, s$name, sep = " | ")

test_that("the list of settings without evidence is the one frozen here", {
  expect_false(anyDuplicated(settings_unrated_frozen) > 0)
  expect_lte(length(settings_unrated_frozen), 103L)
})

test_that("every setting not in the frozen list says what evidence backs it", {
  s <- gr_settings_table()
  key <- settings_key(s)
  rest <- s[!key %in% settings_unrated_frozen, , drop = FALSE]
  expect_gt(nrow(rest), 0L)
  missing <- settings_key(rest)[is.na(rest$status)]
  expect(length(missing) == 0L, paste0(
    "These settings have no evidence status; declare one (\"untested\", \"cited\" or ",
    "\"measured\"):\n  ", paste(missing, collapse = "\n  ")))
  expect_true(all(rest$status %in% c("untested", "cited", "measured")))
})
