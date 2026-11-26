# Core primitives and their callers

Every function the core exports under the `hr_` prefix must have a
caller: a function in the document layer (`R/doc-*.R`) or a test that
uses it. A primitive with neither has no reason to be in the core, and
is removed or moved into a `doc-` file. This file lists each exported
`hr_` function with its callers, and says why the ones the document
layer does not call stay in the core.

The list was made from the installed namespace on 2026-11-22, and the
core functions renamed from gr\_ to hr\_ were added on 2026-11-25:
document layer callers with the boundary test’s parsing
(`tests/testthat/helper-boundary.R`, functions only, plus the schemas
`R/doc-*.R` builds at load), and test callers by searching
`tests/testthat/test-*.R`. A test in
`tests/testthat/test-contract-files.R` fails when an `hr_` export is
missing from the tables below or a row names one that is not exported.
Update this file when an `hr_` export is added, removed or gains or
loses its last caller.

## Called by the document layer

| Function | Callers in the document layer | Tests |
|----|----|----|
| [`hr_agreement()`](https://elkronos.github.io/harnessr/reference/hr_agreement.md) | `agreement_part()`, `reviewer_summary()` | test-core-stats.R, test-screen-reviewers.R |
| [`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md) | [`gr_arm()`](https://elkronos.github.io/harnessr/reference/gr_arm.md) | test-core-bench.R, test-core-bench-report.R |
| [`hr_budget()`](https://elkronos.github.io/harnessr/reference/hr_budget.md) | `cost_stuff()`, [`gr_claims()`](https://elkronos.github.io/harnessr/reference/gr_claims.md), [`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md) and 14 more | test-adversarial.R, test-claims.R and 8 more |
| [`hr_call()`](https://elkronos.github.io/harnessr/reference/hr_call.md) | `answer_request()`, `ledger_answer()`, `read_ensemble()` and 8 more | test-adversarial.R, test-backend.R and 39 more |
| [`hr_check_module()`](https://elkronos.github.io/harnessr/reference/hr_check_module.md) | [`gr_check_reader()`](https://elkronos.github.io/harnessr/reference/gr_check_reader.md), [`gr_check_segmenter()`](https://elkronos.github.io/harnessr/reference/gr_check_segmenter.md) | test-core-contract.R |
| [`hr_client()`](https://elkronos.github.io/harnessr/reference/hr_client.md) | [`answer_document()`](https://elkronos.github.io/harnessr/reference/answer_document.md), `doc_arm_run()`, [`gr_claims()`](https://elkronos.github.io/harnessr/reference/gr_claims.md) and 4 more | test-adversarial.R, test-cache-replay.R and 26 more |
| [`hr_context_fit()`](https://elkronos.github.io/harnessr/reference/hr_context_fit.md) | `read_refine()`, under a read’s `context_policy` | test-context-policy.R |
| [`hr_context_policy()`](https://elkronos.github.io/harnessr/reference/hr_context_policy.md) | `check_context_policy()`, which resolves a read’s `context_policy` | test-context-policy.R |
| [`hr_cost()`](https://elkronos.github.io/harnessr/reference/hr_cost.md) | the reader cost functions: `cost_extract()`, `cost_map_reduce()` and the rest | test-conformance.R, test-core-schema.R |
| [`hr_count_tokens()`](https://elkronos.github.io/harnessr/reference/hr_count_tokens.md) | [`answer_document()`](https://elkronos.github.io/harnessr/reference/answer_document.md), `call_failure()`, `cap_gap_lines()` and 36 more | test-adversarial.R, test-claims.R and 20 more |
| [`hr_effort_escalate()`](https://elkronos.github.io/harnessr/reference/hr_effort_escalate.md) | `read_escalation()`, under a read’s `effort_mode = "escalate"` | test-effort-escalate.R |
| [`hr_effort_event()`](https://elkronos.github.io/harnessr/reference/hr_effort_event.md) | `read_ensemble()`, `read_iterative()` and `read_screen()`, which report triggers | test-effort-escalate.R |
| [`hr_embed()`](https://elkronos.github.io/harnessr/reference/hr_embed.md) | `check_embedder()`, `read_iterative()`, `rerank_prefilter()` and 2 more | test-backend.R, test-cache-replay.R and 14 more |
| [`hr_estimate_cost()`](https://elkronos.github.io/harnessr/reference/hr_estimate_cost.md) | `batch_item_usd()`, `extract_item_usd()`, [`gr_inventory()`](https://elkronos.github.io/harnessr/reference/gr_inventory.md) and 3 more | test-compare-cost.R, test-core-ledger-records.R and 13 more |
| [`hr_ht_estimate()`](https://elkronos.github.io/harnessr/reference/hr_ht_estimate.md) | `screening_recall()` | test-core-stats.R |
| [`hr_mock_client()`](https://elkronos.github.io/harnessr/reference/hr_mock_client.md) | `check_client()` | test-adversarial.R, test-audit-header.R and 110 more |
| [`hr_model_info()`](https://elkronos.github.io/harnessr/reference/hr_model_info.md) | `batch_item_usd()`, `call_failure()`, `extract_item_usd()` and 5 more | test-cache-replay.R, test-context.R and 8 more |
| [`hr_options()`](https://elkronos.github.io/harnessr/reference/hr_options.md) | `check_embedder()`, `corpus_key()`, `embed_counter()` and 14 more | test-adversarial.R, test-backend.R and 65 more |
| [`hr_param()`](https://elkronos.github.io/harnessr/reference/hr_param.md) | the read, segment and ingest schemas (`.gr_read_schema` and the others) | test-core-schema.R, test-settings.R |
| [`hr_prop_ci()`](https://elkronos.github.io/harnessr/reference/hr_prop_ci.md) | `reviewer_summary()`, `screening_recall()` | test-core-stats.R |
| [`hr_reference()`](https://elkronos.github.io/harnessr/reference/hr_reference.md) | [`gr_qa_reference()`](https://elkronos.github.io/harnessr/reference/gr_qa_reference.md) | test-core-bench.R, test-core-bench-report.R |
| [`hr_schema()`](https://elkronos.github.io/harnessr/reference/hr_schema.md) | the read, segment and ingest schemas | test-core-schema.R, test-settings.R |
| [`hr_scorer()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md) | [`gr_scorer_answer()`](https://elkronos.github.io/harnessr/reference/gr_scorer_answer.md) | test-core-bench.R |
| [`hr_signal()`](https://elkronos.github.io/harnessr/reference/hr_signal.md) | `read_ensemble()`, `read_iterative()`, `read_preview()` | test-core-signals.R |
| [`hr_step()`](https://elkronos.github.io/harnessr/reference/hr_step.md) | [`gr_step()`](https://elkronos.github.io/harnessr/reference/gr_step.md), [`gr_step_retrieve()`](https://elkronos.github.io/harnessr/reference/gr_step.md) | test-compose.R, test-reading-options.R |
| [`hr_tokenizer()`](https://elkronos.github.io/harnessr/reference/hr_tokenizer.md) | [`gr_segment()`](https://elkronos.github.io/harnessr/reference/gr_segment.md) | test-core.R, test-parallel.R and 1 more |
| [`hr_trace()`](https://elkronos.github.io/harnessr/reference/hr_trace.md) | [`answer_document()`](https://elkronos.github.io/harnessr/reference/answer_document.md), `check_reader_governor()`, `claims_cost_stage()` and 10 more | test-adversarial.R, test-backend.R and 66 more |
| [`hr_trace_cost()`](https://elkronos.github.io/harnessr/reference/hr_trace_cost.md) | `audit_cost()`, `corpus_cost()`, [`gr_compare()`](https://elkronos.github.io/harnessr/reference/gr_compare.md) and 4 more | test-bench-ctx.R, test-compare-cost.R and 19 more |
| [`hr_trace_summary()`](https://elkronos.github.io/harnessr/reference/hr_trace_summary.md) | `corpus_row()`, [`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md) and `print.gr_answer()` | test-backend.R, test-cache-replay.R and 8 more |
| [`hr_truncate()`](https://elkronos.github.io/harnessr/reference/hr_truncate.md) | `cut_piece()`, which the merge, `hierarchical` and `preview` packers call under a `context_policy` | test-context-policy.R |
| [`hr_truncate_tokens()`](https://elkronos.github.io/harnessr/reference/hr_truncate_tokens.md) | `cap_gap_lines()`, `screen_opening()` and `seg_contextual()` | test-context-policy.R, test-core.R and 5 more |
| [`hr_validate()`](https://elkronos.github.io/harnessr/reference/hr_validate.md) | [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md), [`gr_segment_spec()`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md), [`gr_ingest_spec()`](https://elkronos.github.io/harnessr/reference/gr_ingest_spec.md) | test-core-schema.R, test-adversarial.R |

## Entry points the document layer is handed

A person builds a run with these: a client, its cache or replay, the
model registry and the tokenizer. The document layer receives the client
and the trace they make and does not call these itself. Nothing in them
knows about documents, which is why they are core.

| Function | Tests | Why it is core |
|----|----|----|
| [`hr_api_key()`](https://elkronos.github.io/harnessr/reference/hr_api_key.md) | test-headers.R and test-review6-client.R | Reads the API key a client sends, for any provider. |
| [`hr_backend_client()`](https://elkronos.github.io/harnessr/reference/hr_backend_client.md) | test-backend.R, test-cache-replay.R and 19 more | Wraps any R function as a client. |
| [`hr_cache()`](https://elkronos.github.io/harnessr/reference/hr_cache.md) | test-adversarial.R, test-backend.R and 34 more | An on-disk response cache for any client. |
| [`hr_cache_clear()`](https://elkronos.github.io/harnessr/reference/hr_cache_clear.md) | test-cache-replay.R, test-compat-legacy-keys.R and 2 more | Empties a response cache. |
| [`hr_cache_client()`](https://elkronos.github.io/harnessr/reference/hr_cache_client.md) | test-adversarial.R, test-backend.R and 34 more | Attaches a response cache to any client. |
| [`hr_cache_stats()`](https://elkronos.github.io/harnessr/reference/hr_cache_stats.md) | test-cache-replay.R, test-compat-legacy-keys.R and 5 more | Counts the entries, hits and misses of a response cache. |
| [`hr_ellmer_client()`](https://elkronos.github.io/harnessr/reference/hr_ellmer_client.md) | test-backend.R, test-effort.R and 7 more | Wraps an ellmer chat as a client. |
| [`hr_load_models()`](https://elkronos.github.io/harnessr/reference/hr_load_models.md) | test-core-models-file.R | Registers models and their prices from a CSV file, for any provider. |
| [`hr_model_limits()`](https://elkronos.github.io/harnessr/reference/hr_model_limits.md) | test-core-names.R | The context window and output cap of any registered model. |
| [`hr_models()`](https://elkronos.github.io/harnessr/reference/hr_models.md) | test-hardening.R | Lists the model registry. |
| [`hr_register_model()`](https://elkronos.github.io/harnessr/reference/hr_register_model.md) | test-adversarial.R, test-backend.R and 51 more | Adds or corrects a model in the registry the budgets and costs read. |
| [`hr_replay_client()`](https://elkronos.github.io/harnessr/reference/hr_replay_client.md) | test-adversarial.R, test-backend.R and 22 more | A client that answers from a saved trace, for any run. |
| [`hr_set_tokenizer()`](https://elkronos.github.io/harnessr/reference/hr_set_tokenizer.md) | test-adversarial.R, test-core.R and 5 more | Chooses the tokenizer every token count uses. |
| [`hr_trace_save()`](https://elkronos.github.io/harnessr/reference/hr_trace_save.md) | test-cache-replay.R, test-core-bench.R and 15 more | Writes any trace to a file that hr_replay_client() reads. |

## Called by the tests only

These are the evaluation harness. The document layer produces the runs;
a person uses these functions to compare runs, and the guides
`evaluate`, `compare` and `review` show them doing it. Nothing in the
document layer needs to call them, and nothing in them knows about
documents, which is why they are core. Each has tests of its own.

| Function | Tests | Why it is core |
|----|----|----|
| [`hr_alt_test()`](https://elkronos.github.io/harnessr/reference/hr_alt_test.md) | test-core-stats.R | The alternative annotator test: whether model labels can stand in for a person’s, on any labelled items. |
| [`hr_apply_signal()`](https://elkronos.github.io/harnessr/reference/hr_signal_policy.md) | test-core-signals.R | Applies a signal policy to a recorded signal, for any module. |
| [`hr_assign_splits()`](https://elkronos.github.io/harnessr/reference/hr_assign_splits.md) | test-core-splits.R | Assigns any reference items to splits by cluster. |
| [`hr_baseline_classifier()`](https://elkronos.github.io/harnessr/reference/hr_baseline_classifier.md) | test-core-baseline.R | A cross-fitted text classifier baseline for any labelled items. |
| [`hr_baseline_ranker()`](https://elkronos.github.io/harnessr/reference/hr_baseline_ranker.md) | test-core-baseline.R, test-doc-stop.R | An active-learning screening baseline for any items with text. |
| [`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md) | test-core-bench.R and the other test-core-bench files | Runs any arms against a reference set. |
| [`hr_calibrate_signal()`](https://elkronos.github.io/harnessr/reference/hr_calibrate_signal.md) | test-core-signals.R, test-labels.R | Calibrates a self-signal against graded items, for any module. |
| [`hr_calibration_valid()`](https://elkronos.github.io/harnessr/reference/hr_calibration_valid.md) | test-core-signals.R | Says whether a calibration record is valid for a run. |
| [`hr_chain()`](https://elkronos.github.io/harnessr/reference/hr_chain.md) | test-compose.R | Runs any steps in order as one arm, and derives a chain by dropping or replacing a step. |
| [`hr_contrast()`](https://elkronos.github.io/harnessr/reference/hr_contrast.md) | test-core-bench-ni.R, test-core-bench-sim.R | A non-inferiority contrast between arms, registered before scoring. |
| [`hr_drift_check()`](https://elkronos.github.io/harnessr/reference/hr_drift_check.md) | test-core-bench-drift.R | Checks an arm for drift against a frozen benchmark. |
| [`hr_effort_check()`](https://elkronos.github.io/harnessr/reference/hr_effort_check.md) | test-effort-escalate.R | Compares any effort policy with fixed efforts on a benchmark, with the non-inferiority test. |
| [`hr_effort_log()`](https://elkronos.github.io/harnessr/reference/hr_effort_log.md) | test-effort-escalate.R | The effort raises an escalation policy made on any run’s trace. |
| [`hr_error_correlation()`](https://elkronos.github.io/harnessr/reference/hr_error_correlation.md) | test-pipeline-options.R | Says how far any benchmark’s arms fail on the same items. |
| [`hr_gate_threshold()`](https://elkronos.github.io/harnessr/reference/hr_gate_threshold.md) | test-core-signals.R | Chooses a gate threshold by Learn-then-Test. |
| [`hr_governor()`](https://elkronos.github.io/harnessr/reference/hr_governor.md) | test-core-bench.R, test-claims.R | Limits on what a run may send, which a benchmark shares across its arms. |
| [`hr_judge()`](https://elkronos.github.io/harnessr/reference/hr_judge.md) | test-core-judge.R, test-judge-draws.R | Judges any candidates with a model, in more than one order. |
| [`hr_judge_config()`](https://elkronos.github.io/harnessr/reference/hr_judge_config.md) | test-core-judge.R, test-labels.R | A judge configuration. |
| [`hr_judge_ppi()`](https://elkronos.github.io/harnessr/reference/hr_judge_ppi.md) | test-core-judge.R | Corrects judge scores with a few human labels. |
| [`hr_judge_valid()`](https://elkronos.github.io/harnessr/reference/hr_judge_validate.md) | test-core-judge.R | Says whether a validation record still holds for a judge configuration. |
| [`hr_judge_validate()`](https://elkronos.github.io/harnessr/reference/hr_judge_validate.md) | test-core-judge.R, test-labels.R | Validates a judge against blind human labels. |
| [`hr_mdd()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md) | test-core-bench-ni.R | The minimum detectable difference of a paired, clustered design. |
| [`hr_modules()`](https://elkronos.github.io/harnessr/reference/hr_modules.md) | test-registry-modules.R | Lists the registered modules of every kind in one table, through each kind’s `get` function; nothing in it names a kind. |
| [`hr_n_needed()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md) | test-core-bench-ni.R | The number of items needed to detect a given difference. |
| [`hr_ppi()`](https://elkronos.github.io/harnessr/reference/hr_ppi.md) | test-core-stats.R, test-core-judge.R | Prediction-powered inference on any scores. |
| [`hr_reference_add()`](https://elkronos.github.io/harnessr/reference/hr_reference.md) | test-core-bench.R | Adds items to a reference set. |
| [`hr_register()`](https://elkronos.github.io/harnessr/reference/hr_register.md) | test-registry-modules.R | Registers a module of any kind through the `set` function the kind’s layer gave; the document layer’s kinds run their gr_register\_\*() checks. |
| [`hr_register_contrasts()`](https://elkronos.github.io/harnessr/reference/hr_contrast.md) | test-core-bench-ni.R, test-core-bench-sim.R | Registers contrasts with a reference before scoring. |
| [`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md) | test-core-bench-report.R and the other test-core-bench files | Reports a benchmark with intervals. |
| [`hr_scorer_exact()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md) | test-core-bench.R, test-core-judge.R | A scoring rule for exact matches, for any outputs. |
| [`hr_scorer_judge()`](https://elkronos.github.io/harnessr/reference/hr_scorer_judge.md) | test-core-judge.R | Scores benchmark runs with a validated judge. |
| [`hr_set()`](https://elkronos.github.io/harnessr/reference/hr_set.md) | test-compose.R, test-sweep.R | Builds a step or a chain again with some settings changed by “step.setting” path, for any steps with schemas. |
| [`hr_settings()`](https://elkronos.github.io/harnessr/reference/hr_settings.md) | test-compose.R | Lists every setting of a step or a chain by path, with its value, default, range and evidence. |
| [`hr_skill()`](https://elkronos.github.io/harnessr/reference/hr_skill.md) | test-skill.R | Reads a skill folder a person chose, for a step of any chain; nothing in it knows about documents. |
| [`hr_signal_policy()`](https://elkronos.github.io/harnessr/reference/hr_signal_policy.md) | test-core-signals.R | What a signal may do, and what happens when it may not. |
| [`hr_signals()`](https://elkronos.github.io/harnessr/reference/hr_signal.md) | test-core-signals.R | The self-signals a run recorded. |
| [`hr_step_command()`](https://elkronos.github.io/harnessr/reference/hr_step_command.md) | test-command.R, test-settings-table.R | A chain step that runs a program the user names and reads its result, for any chain. |
| [`hr_sweep()`](https://elkronos.github.io/harnessr/reference/hr_sweep.md) | test-sweep.R | Builds one arm per row of a grid of settings, for any module with a schema. |
| [`hr_sweep_check()`](https://elkronos.github.io/harnessr/reference/hr_sweep_check.md) | test-sweep.R | Finds the settings of a sweep that changed nothing that was sent. |
| [`hr_tfidf()`](https://elkronos.github.io/harnessr/reference/hr_tfidf.md) | test-core-baseline.R | Tf-idf features from any texts, behind the baselines. |

## Without a caller

None. Every exported `hr_` function has a caller in the document layer
or a test.

## Other parts of the core under review

- `tests/testthat/fixtures/boundary/allowed.csv` holds only its header:
  the core makes no call into the document layer. The last three calls
  went with the module registry.
  [`hr_embed()`](https://elkronos.github.io/harnessr/reference/hr_embed.md)
  reads embedders through the embedder kind’s accessor instead of
  calling `resolve_embedder()` and `lexical_embed()`, and
  `segment_effort()` (`R/core-effort-static.R`) reads a segmenter’s
  `effort_label` through the segmenter kind’s accessor instead of
  calling `segment_effort_label()`, which is deleted.
- `tests/testthat/fixtures/boundary/doc-uses-internal.csv` lists the
  core functions that are not exported and that the document layer still
  uses. The list may only shrink.
- The refactor plan also named an effective-window probe. No function in
  `R/` probes a model’s context window: the core reads it from the model
  table
  ([`hr_model_info()`](https://elkronos.github.io/harnessr/reference/hr_model_info.md),
  filled by
  [`hr_register_model()`](https://elkronos.github.io/harnessr/reference/hr_register_model.md)),
  so there is nothing to review.
