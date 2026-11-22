# Core primitives and their callers

Every function the core exports under the `hr_` prefix must have a
caller: a function in the document layer (`R/doc-*.R`) or a test that
uses it. A primitive with neither has no reason to be in the core, and
is removed or moved into a `doc-` file. This file lists each exported
`hr_` function with its callers, and says why the ones the document
layer does not call stay in the core.

The list was made from the installed namespace on 2026-11-22: document
layer callers with the boundary test’s parsing
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
| [`hr_check_module()`](https://elkronos.github.io/harnessr/reference/hr_check_module.md) | [`gr_check_reader()`](https://elkronos.github.io/harnessr/reference/gr_check_reader.md), [`gr_check_segmenter()`](https://elkronos.github.io/harnessr/reference/gr_check_segmenter.md) | test-core-contract.R |
| [`hr_context_fit()`](https://elkronos.github.io/harnessr/reference/hr_context_fit.md) | `read_refine()`, under a read’s `context_policy` | test-context-policy.R |
| [`hr_context_policy()`](https://elkronos.github.io/harnessr/reference/hr_context_policy.md) | `check_context_policy()`, which resolves a read’s `context_policy` | test-context-policy.R |
| [`hr_cost()`](https://elkronos.github.io/harnessr/reference/hr_cost.md) | the reader cost functions: `cost_extract()`, `cost_map_reduce()` and the rest | test-conformance.R, test-core-schema.R |
| [`hr_effort_escalate()`](https://elkronos.github.io/harnessr/reference/hr_effort_escalate.md) | `read_escalation()`, under a read’s `effort_mode = "escalate"` | test-effort-escalate.R |
| [`hr_effort_event()`](https://elkronos.github.io/harnessr/reference/hr_effort_event.md) | `read_ensemble()`, `read_iterative()` and `read_screen()`, which report triggers | test-effort-escalate.R |
| [`hr_ht_estimate()`](https://elkronos.github.io/harnessr/reference/hr_ht_estimate.md) | `screening_recall()` | test-core-stats.R |
| [`hr_param()`](https://elkronos.github.io/harnessr/reference/hr_param.md) | the read, segment and ingest schemas (`.gr_read_schema` and the others) | test-core-schema.R, test-settings.R |
| [`hr_prop_ci()`](https://elkronos.github.io/harnessr/reference/hr_prop_ci.md) | `reviewer_summary()`, `screening_recall()` | test-core-stats.R |
| [`hr_reference()`](https://elkronos.github.io/harnessr/reference/hr_reference.md) | [`gr_qa_reference()`](https://elkronos.github.io/harnessr/reference/gr_qa_reference.md) | test-core-bench.R, test-core-bench-report.R |
| [`hr_schema()`](https://elkronos.github.io/harnessr/reference/hr_schema.md) | the read, segment and ingest schemas | test-core-schema.R, test-settings.R |
| [`hr_scorer()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md) | [`gr_scorer_answer()`](https://elkronos.github.io/harnessr/reference/gr_scorer_answer.md) | test-core-bench.R |
| [`hr_signal()`](https://elkronos.github.io/harnessr/reference/hr_signal.md) | `read_ensemble()`, `read_iterative()`, `read_preview()` | test-core-signals.R |
| [`hr_step()`](https://elkronos.github.io/harnessr/reference/hr_step.md) | [`gr_step()`](https://elkronos.github.io/harnessr/reference/gr_step.md), [`gr_step_retrieve()`](https://elkronos.github.io/harnessr/reference/gr_step.md) | test-compose.R, test-reading-options.R |
| [`hr_truncate()`](https://elkronos.github.io/harnessr/reference/hr_truncate.md) | `cut_piece()`, which the merge, `hierarchical` and `preview` packers call under a `context_policy` | test-context-policy.R |
| [`hr_validate()`](https://elkronos.github.io/harnessr/reference/hr_validate.md) | [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md), [`gr_segment_spec()`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md), [`gr_ingest_spec()`](https://elkronos.github.io/harnessr/reference/gr_ingest_spec.md) | test-core-schema.R, test-adversarial.R |

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
| [`hr_n_needed()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md) | test-core-bench-ni.R | The number of items needed to detect a given difference. |
| [`hr_ppi()`](https://elkronos.github.io/harnessr/reference/hr_ppi.md) | test-core-stats.R, test-core-judge.R | Prediction-powered inference on any scores. |
| [`hr_reference_add()`](https://elkronos.github.io/harnessr/reference/hr_reference.md) | test-core-bench.R | Adds items to a reference set. |
| [`hr_register_contrasts()`](https://elkronos.github.io/harnessr/reference/hr_contrast.md) | test-core-bench-ni.R, test-core-bench-sim.R | Registers contrasts with a reference before scoring. |
| [`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md) | test-core-bench-report.R and the other test-core-bench files | Reports a benchmark with intervals. |
| [`hr_scorer_exact()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md) | test-core-bench.R, test-core-judge.R | A scoring rule for exact matches, for any outputs. |
| [`hr_scorer_judge()`](https://elkronos.github.io/harnessr/reference/hr_scorer_judge.md) | test-core-judge.R | Scores benchmark runs with a validated judge. |
| [`hr_signal_policy()`](https://elkronos.github.io/harnessr/reference/hr_signal_policy.md) | test-core-signals.R | What a signal may do, and what happens when it may not. |
| [`hr_signals()`](https://elkronos.github.io/harnessr/reference/hr_signal.md) | test-core-signals.R | The self-signals a run recorded. |
| [`hr_sweep()`](https://elkronos.github.io/harnessr/reference/hr_sweep.md) | test-sweep.R | Builds one arm per row of a grid of settings, for any module with a schema. |
| [`hr_sweep_check()`](https://elkronos.github.io/harnessr/reference/hr_sweep_check.md) | test-sweep.R | Finds the settings of a sweep that changed nothing that was sent. |
| [`hr_tfidf()`](https://elkronos.github.io/harnessr/reference/hr_tfidf.md) | test-core-baseline.R | Tf-idf features from any texts, behind the baselines. |

## Without a caller

None. Every exported `hr_` function has a caller in the document layer
or a test.

## Other parts of the core under review

- `tests/testthat/fixtures/boundary/allowed.csv` lists three calls from
  the core into the document layer, each with the change that removes
  it:
  - The embedding request path,
    [`gr_embed()`](https://elkronos.github.io/harnessr/reference/gr_embed.md),
    calls `resolve_embedder()` and `lexical_embed()`. These go when
    embedders become a registered module kind and the core looks them up
    in the registry.
  - `segment_effort()` (`R/core-effort-static.R`) hands a segmenter the
    effort its own requests resolve to, and calls
    `segment_effort_label()` (`R/doc-segment-run.R`) to learn the label
    a built-in segmenter’s requests carry. This goes when each segmenter
    declares its own call stems and the label function is deleted.
- `tests/testthat/fixtures/boundary/doc-uses-internal.csv` lists the
  core functions that are not exported and that the document layer still
  uses. The list may only shrink.
- The refactor plan also named an effective-window probe. No function in
  `R/` probes a model’s context window: the core reads it from the model
  table
  ([`gr_model_info()`](https://elkronos.github.io/harnessr/reference/gr_model_info.md),
  filled by
  [`gr_register_model()`](https://elkronos.github.io/harnessr/reference/gr_register_model.md)),
  so there is nothing to review.
