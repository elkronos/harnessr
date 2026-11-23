# Core primitives and their callers

Every function the core exports under the `hr_` prefix must have a caller:
a function in the document layer (`R/doc-*.R`) or a test that uses it. A
primitive with neither has no reason to be in the core, and is removed or
moved into a `doc-` file. This file lists each exported `hr_` function with
its callers, and says why the ones the document layer does not call stay in
the core.

The list was made from the installed namespace on 2026-11-22: document layer
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
| `hr_check_module()` | `gr_check_reader()`, `gr_check_segmenter()` | test-core-contract.R |
| `hr_context_fit()` | `read_refine()`, under a read's `context_policy` | test-context-policy.R |
| `hr_context_policy()` | `check_context_policy()`, which resolves a read's `context_policy` | test-context-policy.R |
| `hr_cost()` | the reader cost functions: `cost_extract()`, `cost_map_reduce()` and the rest | test-conformance.R, test-core-schema.R |
| `hr_effort_escalate()` | `read_escalation()`, under a read's `effort_mode = "escalate"` | test-effort-escalate.R |
| `hr_effort_event()` | `read_ensemble()`, `read_iterative()` and `read_screen()`, which report triggers | test-effort-escalate.R |
| `hr_ht_estimate()` | `screening_recall()` | test-core-stats.R |
| `hr_param()` | the read, segment and ingest schemas (`.gr_read_schema` and the others) | test-core-schema.R, test-settings.R |
| `hr_prop_ci()` | `reviewer_summary()`, `screening_recall()` | test-core-stats.R |
| `hr_reference()` | `gr_qa_reference()` | test-core-bench.R, test-core-bench-report.R |
| `hr_schema()` | the read, segment and ingest schemas | test-core-schema.R, test-settings.R |
| `hr_scorer()` | `gr_scorer_answer()` | test-core-bench.R |
| `hr_signal()` | `read_ensemble()`, `read_iterative()`, `read_preview()` | test-core-signals.R |
| `hr_step()` | `gr_step()`, `gr_step_retrieve()` | test-compose.R, test-reading-options.R |
| `hr_truncate()` | `cut_piece()`, which the merge, `hierarchical` and `preview` packers call under a `context_policy` | test-context-policy.R |
| `hr_validate()` | `gr_read_spec()`, `gr_segment_spec()`, `gr_ingest_spec()` | test-core-schema.R, test-adversarial.R |

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
| `hr_n_needed()` | test-core-bench-ni.R | The number of items needed to detect a given difference. |
| `hr_ppi()` | test-core-stats.R, test-core-judge.R | Prediction-powered inference on any scores. |
| `hr_reference_add()` | test-core-bench.R | Adds items to a reference set. |
| `hr_register_contrasts()` | test-core-bench-ni.R, test-core-bench-sim.R | Registers contrasts with a reference before scoring. |
| `hr_report()` | test-core-bench-report.R and the other test-core-bench files | Reports a benchmark with intervals. |
| `hr_scorer_exact()` | test-core-bench.R, test-core-judge.R | A scoring rule for exact matches, for any outputs. |
| `hr_scorer_judge()` | test-core-judge.R | Scores benchmark runs with a validated judge. |
| `hr_set()` | test-compose.R, test-sweep.R | Builds a step or a chain again with some settings changed by "step.setting" path, for any steps with schemas. |
| `hr_settings()` | test-compose.R | Lists every setting of a step or a chain by path, with its value, default, range and evidence. |
| `hr_signal_policy()` | test-core-signals.R | What a signal may do, and what happens when it may not. |
| `hr_signals()` | test-core-signals.R | The self-signals a run recorded. |
| `hr_sweep()` | test-sweep.R | Builds one arm per row of a grid of settings, for any module with a schema. |
| `hr_sweep_check()` | test-sweep.R | Finds the settings of a sweep that changed nothing that was sent. |
| `hr_tfidf()` | test-core-baseline.R | Tf-idf features from any texts, behind the baselines. |

## Without a caller

None. Every exported `hr_` function has a caller in the document layer or a
test.

## Other parts of the core under review

- `tests/testthat/fixtures/boundary/allowed.csv` lists three calls from the
  core into the document layer, each with the change that removes it:
  - The embedding request path, `gr_embed()`, calls `resolve_embedder()` and
    `lexical_embed()`. These go when embedders become a registered module
    kind and the core looks them up in the registry.
  - `segment_effort()` (`R/core-effort-static.R`) hands a segmenter the
    effort its own requests resolve to, and calls `segment_effort_label()`
    (`R/doc-segment-run.R`) to learn the label a built-in segmenter's
    requests carry. This goes when each segmenter declares its own call
    stems and the label function is deleted.
- `tests/testthat/fixtures/boundary/doc-uses-internal.csv` lists the core
  functions that are not exported and that the document layer still uses.
  The list may only shrink.
- The refactor plan also named an effective-window probe. No function in
  `R/` probes a model's context window: the core reads it from the model
  table (`gr_model_info()`, filled by `gr_register_model()`), so there is
  nothing to review.
