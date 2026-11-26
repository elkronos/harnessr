# Core primitives and their callers

Every function the core exports under the `hr_` prefix must have a caller:
a function in the document layer (`R/doc-*.R`) or a test that uses it. A
primitive with neither has no reason to be in the core, and is removed or
moved into a `doc-` file. This file lists each exported `hr_` function with
its callers, and says why the ones the document layer does not call stay in
the core.

The list was made from the installed namespace on 2026-11-22, and the core
functions renamed from gr_ to hr_ were added on 2026-11-25: document layer
callers with the boundary test's parsing (`tests/testthat/helper-boundary.R`,
functions only, plus the schemas `R/doc-*.R` builds at load), and test
callers by searching `tests/testthat/test-*.R`. A test in
`tests/testthat/test-contract-files.R` fails when an `hr_` export is missing
from the tables below or a row names one that is not exported. Update this file when an `hr_` export is added,
removed or gains or loses its last caller.

## Called by the document layer

| Function | Callers in the document layer | Tests |
|---|---|---|
| `hr_agreement()` | `agreement_part()`, `reviewer_summary()` | test-core-stats.R, test-screen-reviewers.R |
| `hr_arm()` | `gr_arm()` | test-core-bench.R, test-core-bench-report.R |
| `hr_budget()` | `cost_stuff()`, `gr_claims()`, `gr_synthesise()` and 14 more | test-adversarial.R, test-claims.R and 8 more |
| `hr_call()` | `answer_request()`, `ledger_answer()`, `read_ensemble()` and 8 more | test-adversarial.R, test-backend.R and 39 more |
| `hr_check_module()` | `gr_check_reader()`, `gr_check_segmenter()` | test-core-contract.R |
| `hr_client()` | `answer_document()`, `doc_arm_run()`, `gr_claims()` and 4 more | test-adversarial.R, test-cache-replay.R and 26 more |
| `hr_context_fit()` | `read_refine()`, under a read's `context_policy` | test-context-policy.R |
| `hr_context_policy()` | `check_context_policy()`, which resolves a read's `context_policy` | test-context-policy.R |
| `hr_cost()` | the reader cost functions: `cost_extract()`, `cost_map_reduce()` and the rest | test-conformance.R, test-core-schema.R |
| `hr_count_tokens()` | `answer_document()`, `call_failure()`, `cap_gap_lines()` and 36 more | test-adversarial.R, test-claims.R and 20 more |
| `hr_effort_escalate()` | `read_escalation()`, under a read's `effort_mode = "escalate"` | test-effort-escalate.R |
| `hr_effort_event()` | `read_ensemble()`, `read_iterative()` and `read_screen()`, which report triggers | test-effort-escalate.R |
| `hr_embed()` | `check_embedder()`, `read_iterative()`, `rerank_prefilter()` and 2 more | test-backend.R, test-cache-replay.R and 14 more |
| `hr_estimate_cost()` | `batch_item_usd()`, `extract_item_usd()`, `gr_inventory()` and 3 more | test-compare-cost.R, test-core-ledger-records.R and 13 more |
| `hr_ht_estimate()` | `screening_recall()` | test-core-stats.R |
| `hr_mock_client()` | `check_client()` | test-adversarial.R, test-audit-header.R and 110 more |
| `hr_model_info()` | `batch_item_usd()`, `call_failure()`, `extract_item_usd()` and 5 more | test-cache-replay.R, test-context.R and 8 more |
| `hr_options()` | `check_embedder()`, `corpus_key()`, `embed_counter()` and 14 more | test-adversarial.R, test-backend.R and 65 more |
| `hr_param()` | the read, segment and ingest schemas (`.gr_read_schema` and the others) | test-core-schema.R, test-settings.R |
| `hr_prop_ci()` | `reviewer_summary()`, `screening_recall()` | test-core-stats.R |
| `hr_reference()` | `gr_qa_reference()` | test-core-bench.R, test-core-bench-report.R |
| `hr_schema()` | the read, segment and ingest schemas | test-core-schema.R, test-settings.R |
| `hr_scorer()` | `gr_scorer_answer()` | test-core-bench.R |
| `hr_signal()` | `read_ensemble()`, `read_iterative()`, `read_preview()` | test-core-signals.R |
| `hr_step()` | `gr_step()`, `gr_step_retrieve()` | test-compose.R, test-reading-options.R |
| `hr_tokenizer()` | `gr_segment()` | test-core.R, test-parallel.R and 1 more |
| `hr_trace()` | `answer_document()`, `check_reader_governor()`, `claims_cost_stage()` and 10 more | test-adversarial.R, test-backend.R and 66 more |
| `hr_trace_cost()` | `audit_cost()`, `corpus_cost()`, `gr_compare()` and 4 more | test-bench-ctx.R, test-compare-cost.R and 19 more |
| `hr_trace_summary()` | `corpus_row()`, `gr_read_many()` and `print.gr_answer()` | test-backend.R, test-cache-replay.R and 8 more |
| `hr_truncate()` | `cut_piece()`, which the merge, `hierarchical` and `preview` packers call under a `context_policy` | test-context-policy.R |
| `hr_truncate_tokens()` | `cap_gap_lines()`, `screen_opening()` and `seg_contextual()` | test-context-policy.R, test-core.R and 5 more |
| `hr_validate()` | `gr_read_spec()`, `gr_segment_spec()`, `gr_ingest_spec()` | test-core-schema.R, test-adversarial.R |

## Entry points the document layer is handed

A person builds a run with these: a client, its cache or replay, the model
registry and the tokenizer. The document layer receives the client and
the trace they make and does not call these itself. Nothing in them knows
about documents, which is why they are core.

| Function | Tests | Why it is core |
|---|---|---|
| `hr_api_key()` | test-headers.R and test-review6-client.R | Reads the API key a client sends, for any provider. |
| `hr_backend_client()` | test-backend.R, test-cache-replay.R and 19 more | Wraps any R function as a client. |
| `hr_cache()` | test-adversarial.R, test-backend.R and 34 more | An on-disk response cache for any client. |
| `hr_cache_clear()` | test-cache-replay.R, test-compat-legacy-keys.R and 2 more | Empties a response cache. |
| `hr_cache_client()` | test-adversarial.R, test-backend.R and 34 more | Attaches a response cache to any client. |
| `hr_cache_stats()` | test-cache-replay.R, test-compat-legacy-keys.R and 5 more | Counts the entries, hits and misses of a response cache. |
| `hr_ellmer_client()` | test-backend.R, test-effort.R and 7 more | Wraps an ellmer chat as a client. |
| `hr_load_models()` | test-core-models-file.R | Registers models and their prices from a CSV file, for any provider. |
| `hr_model_limits()` | test-core-names.R | The context window and output cap of any registered model. |
| `hr_models()` | test-hardening.R | Lists the model registry. |
| `hr_register_model()` | test-adversarial.R, test-backend.R and 51 more | Adds or corrects a model in the registry the budgets and costs read. |
| `hr_replay_client()` | test-adversarial.R, test-backend.R and 22 more | A client that answers from a saved trace, for any run. |
| `hr_set_tokenizer()` | test-adversarial.R, test-core.R and 5 more | Chooses the tokenizer every token count uses. |
| `hr_trace_save()` | test-cache-replay.R, test-core-bench.R and 15 more | Writes any trace to a file that hr_replay_client() reads. |

## Called by the tests only

These are the evaluation harness. The document layer produces the runs; a
person uses these functions to compare runs, and the guides `evaluate`,
`compare` and `review` show them doing it. Nothing in the document layer
needs to call them, and nothing in them knows about documents, which is why
they are core. Each has tests of its own.

| Function | Tests | Why it is core |
|---|---|---|
| `hr_alt_test()` | test-core-stats.R | The alternative annotator test: whether model labels can stand in for a person's, on any labelled items. |
| `hr_apply_signal()` | test-core-signals.R | Applies a signal policy to a recorded signal, for any module. |
| `hr_assign_splits()` | test-core-splits.R | Assigns any reference items to splits by cluster. |
| `hr_baseline_classifier()` | test-core-baseline.R | A cross-fitted text classifier baseline for any labelled items. |
| `hr_baseline_ranker()` | test-core-baseline.R, test-doc-stop.R | An active-learning screening baseline for any items with text. |
| `hr_benchmark()` | test-core-bench.R and the other test-core-bench files | Runs any arms against a reference set. |
| `hr_calibrate_signal()` | test-core-signals.R, test-labels.R | Calibrates a self-signal against graded items, for any module. |
| `hr_calibration_valid()` | test-core-signals.R | Says whether a calibration record is valid for a run. |
| `hr_chain()` | test-compose.R | Runs any steps in order as one arm, and derives a chain by dropping or replacing a step. |
| `hr_contrast()` | test-core-bench-ni.R, test-core-bench-sim.R | A non-inferiority contrast between arms, registered before scoring. |
| `hr_drift_check()` | test-core-bench-drift.R | Checks an arm for drift against a frozen benchmark. |
| `hr_effort_check()` | test-effort-escalate.R | Compares any effort policy with fixed efforts on a benchmark, with the non-inferiority test. |
| `hr_effort_log()` | test-effort-escalate.R | The effort raises an escalation policy made on any run's trace. |
| `hr_error_correlation()` | test-pipeline-options.R | Says how far any benchmark's arms fail on the same items. |
| `hr_gate_threshold()` | test-core-signals.R | Chooses a gate threshold by Learn-then-Test. |
| `hr_governor()` | test-core-bench.R, test-claims.R | Limits on what a run may send, which a benchmark shares across its arms. |
| `hr_judge()` | test-core-judge.R, test-judge-draws.R | Judges any candidates with a model, in more than one order. |
| `hr_judge_config()` | test-core-judge.R, test-labels.R | A judge configuration. |
| `hr_judge_ppi()` | test-core-judge.R | Corrects judge scores with a few human labels. |
| `hr_judge_valid()` | test-core-judge.R | Says whether a validation record still holds for a judge configuration. |
| `hr_judge_validate()` | test-core-judge.R, test-labels.R | Validates a judge against blind human labels. |
| `hr_mdd()` | test-core-bench-ni.R | The minimum detectable difference of a paired, clustered design. |
| `hr_modules()` | test-registry-modules.R | Lists the registered modules of every kind in one table, through each kind's `get` function; nothing in it names a kind. |
| `hr_n_needed()` | test-core-bench-ni.R | The number of items needed to detect a given difference. |
| `hr_ppi()` | test-core-stats.R, test-core-judge.R | Prediction-powered inference on any scores. |
| `hr_reference_add()` | test-core-bench.R | Adds items to a reference set. |
| `hr_register()` | test-registry-modules.R | Registers a module of any kind through the `set` function the kind's layer gave; the document layer's kinds run their gr_register_*() checks. |
| `hr_register_contrasts()` | test-core-bench-ni.R, test-core-bench-sim.R | Registers contrasts with a reference before scoring. |
| `hr_report()` | test-core-bench-report.R and the other test-core-bench files | Reports a benchmark with intervals. |
| `hr_scorer_exact()` | test-core-bench.R, test-core-judge.R | A scoring rule for exact matches, for any outputs. |
| `hr_scorer_judge()` | test-core-judge.R | Scores benchmark runs with a validated judge. |
| `hr_set()` | test-compose.R, test-sweep.R | Builds a step or a chain again with some settings changed by "step.setting" path, for any steps with schemas. |
| `hr_settings()` | test-compose.R | Lists every setting of a step or a chain by path, with its value, default, range and evidence. |
| `hr_skill()` | test-skill.R | Reads a skill folder a person chose, for a step of any chain; nothing in it knows about documents. |
| `hr_signal_policy()` | test-core-signals.R | What a signal may do, and what happens when it may not. |
| `hr_signals()` | test-core-signals.R | The self-signals a run recorded. |
| `hr_step_command()` | test-command.R, test-settings-table.R | A chain step that runs a program the user names and reads its result, for any chain. |
| `hr_sweep()` | test-sweep.R | Builds one arm per row of a grid of settings, for any module with a schema. |
| `hr_sweep_check()` | test-sweep.R | Finds the settings of a sweep that changed nothing that was sent. |
| `hr_tfidf()` | test-core-baseline.R | Tf-idf features from any texts, behind the baselines. |

## Without a caller

None. Every exported `hr_` function has a caller in the document layer or a
test.

## Other parts of the core under review

- `tests/testthat/fixtures/boundary/allowed.csv` holds only its header: the
  core makes no call into the document layer. The last three calls went with
  the module registry. `hr_embed()` reads embedders through the embedder
  kind's accessor instead of calling `resolve_embedder()` and
  `lexical_embed()`, and `segment_effort()` (`R/core-effort-static.R`)
  reads a segmenter's `effort_label` through the segmenter kind's accessor
  instead of calling `segment_effort_label()`, which is deleted.
- `tests/testthat/fixtures/boundary/doc-uses-internal.csv` lists the core
  functions that are not exported and that the document layer still uses.
  The list may only shrink.
- The refactor plan also named an effective-window probe. No function in
  `R/` probes a model's context window: the core reads it from the model
  table (`hr_model_info()`, filled by `hr_register_model()`), so there is
  nothing to review.
