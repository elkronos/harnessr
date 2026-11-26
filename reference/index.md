# Package index

## Core

The harness for model calls, with or without a document: calls and
clients, models and prices, context, effort, limits, caching and replay,
composition and measurement. The groups follow the core guides in order,
starting with
[`vignette("core")`](https://elkronos.github.io/harnessr/articles/core.md).

### Calls, clients and results

One call to a model, the result it returns and the trace that records
it. Clients for OpenAI-compatible endpoints, any provider ellmer
supports, any function you write, and an offline stand-in for practice
and tests. Signals a run records about its own work, and the schemas
that check settings. See
[`vignette("core")`](https://elkronos.github.io/harnessr/articles/core.md).

- [`hr_call()`](https://elkronos.github.io/harnessr/reference/hr_call.md)
  : Call a model
- [`gr_result`](https://elkronos.github.io/harnessr/reference/gr_result.md)
  : The result of one model call
- [`hr_client()`](https://elkronos.github.io/harnessr/reference/hr_client.md)
  : Construct a model client
- [`hr_api_key()`](https://elkronos.github.io/harnessr/reference/hr_api_key.md)
  : Resolve the API key
- [`hr_ellmer_client()`](https://elkronos.github.io/harnessr/reference/hr_ellmer_client.md)
  : Read documents through an ellmer chat
- [`hr_backend_client()`](https://elkronos.github.io/harnessr/reference/hr_backend_client.md)
  : Use any function as the model transport
- [`hr_mock_client()`](https://elkronos.github.io/harnessr/reference/hr_mock_client.md)
  : A deterministic offline client for tests, demos and dry runs
- [`hr_embed()`](https://elkronos.github.io/harnessr/reference/hr_embed.md)
  : Embed texts
- [`hr_trace()`](https://elkronos.github.io/harnessr/reference/hr_trace.md)
  [`as.data.frame(`*`<gr_trace>`*`)`](https://elkronos.github.io/harnessr/reference/hr_trace.md)
  : Create a run trace
- [`hr_trace_summary()`](https://elkronos.github.io/harnessr/reference/hr_trace_summary.md)
  : Summarise a trace
- [`hr_trace_cost()`](https://elkronos.github.io/harnessr/reference/hr_trace_cost.md)
  : What a run actually cost
- [`hr_trace_save()`](https://elkronos.github.io/harnessr/reference/hr_trace_save.md)
  : Save a trace to a file
- [`as_json()`](https://elkronos.github.io/harnessr/reference/as_json.md)
  : Serialise an object to JSON
- [`hr_signal()`](https://elkronos.github.io/harnessr/reference/hr_signal.md)
  [`hr_signals()`](https://elkronos.github.io/harnessr/reference/hr_signal.md)
  : Record a self-signal
- [`hr_param()`](https://elkronos.github.io/harnessr/reference/hr_param.md)
  : Declare one parameter of a module or spec
- [`hr_schema()`](https://elkronos.github.io/harnessr/reference/hr_schema.md)
  [`as.data.frame(`*`<hr_schema>`*`)`](https://elkronos.github.io/harnessr/reference/hr_schema.md)
  : Collect parameters into a schema
- [`hr_validate()`](https://elkronos.github.io/harnessr/reference/hr_validate.md)
  : Validate and resolve settings against a schema

### Models, prices and tokens

The model registry, the prices you set, cost estimates and token counts.
See
[`vignette("models")`](https://elkronos.github.io/harnessr/articles/models.md).

- [`hr_models()`](https://elkronos.github.io/harnessr/reference/hr_models.md)
  : List every known model
- [`hr_model_info()`](https://elkronos.github.io/harnessr/reference/hr_model_info.md)
  : Look up a model's capabilities
- [`hr_model_limits()`](https://elkronos.github.io/harnessr/reference/hr_model_limits.md)
  : Context and output limits for a model
- [`hr_register_model()`](https://elkronos.github.io/harnessr/reference/hr_register_model.md)
  : Register a model, or set the prices of a known one
- [`hr_load_models()`](https://elkronos.github.io/harnessr/reference/hr_load_models.md)
  : Register models from a CSV file
- [`hr_estimate_cost()`](https://elkronos.github.io/harnessr/reference/hr_estimate_cost.md)
  : Estimate the USD cost of a set of calls
- [`hr_count_tokens()`](https://elkronos.github.io/harnessr/reference/hr_count_tokens.md)
  : Count tokens in text
- [`hr_tokenizer()`](https://elkronos.github.io/harnessr/reference/hr_tokenizer.md)
  : The active tokenizer
- [`hr_set_tokenizer()`](https://elkronos.github.io/harnessr/reference/hr_set_tokenizer.md)
  : Register or inspect the active tokenizer

### Context

How much room a prompt has, fitting its pieces into that room, and
cutting one piece. See
[`vignette("context")`](https://elkronos.github.io/harnessr/articles/context.md).

- [`hr_budget()`](https://elkronos.github.io/harnessr/reference/hr_budget.md)
  : Compute a usable input-token budget for one model call

- [`hr_context_fit()`](https://elkronos.github.io/harnessr/reference/hr_context_fit.md)
  : Fit named pieces of text into a token budget under a context policy

- [`hr_context_policy()`](https://elkronos.github.io/harnessr/reference/hr_context_policy.md)
  [`print(`*`<hr_context_policy>`*`)`](https://elkronos.github.io/harnessr/reference/hr_context_policy.md)
  : Rules for what a request keeps when its text does not fit

- [`hr_truncate()`](https://elkronos.github.io/harnessr/reference/hr_truncate.md)
  : Cut text to a token count, keeping the part you choose

- [`hr_truncate_tokens()`](https://elkronos.github.io/harnessr/reference/hr_truncate_tokens.md)
  :

  Truncate text to at most `n` tokens

### Effort

Raising reasoning effort when a stage goes wrong, the log of each raise,
and checking whether more effort pays. See
[`vignette("effort")`](https://elkronos.github.io/harnessr/articles/effort.md).

- [`hr_effort_escalate()`](https://elkronos.github.io/harnessr/reference/hr_effort_escalate.md)
  [`print(`*`<hr_effort_escalate>`*`)`](https://elkronos.github.io/harnessr/reference/hr_effort_escalate.md)
  : Reasoning effort that is raised for the next stage when a trigger
  fires
- [`hr_effort_event()`](https://elkronos.github.io/harnessr/reference/hr_effort_event.md)
  : Report a trigger for an effort escalation
- [`hr_effort_log()`](https://elkronos.github.io/harnessr/reference/hr_effort_log.md)
  : The effort raises of a run
- [`hr_effort_check()`](https://elkronos.github.io/harnessr/reference/hr_effort_check.md)
  [`print(`*`<hr_effort_check>`*`)`](https://elkronos.github.io/harnessr/reference/hr_effort_check.md)
  : Compare an effort policy with fixed efforts on a benchmark

### Limits, caching and replay

Settings and spending limits, paying for a request once, and replaying a
recorded run without a model. See
[`vignette("runs")`](https://elkronos.github.io/harnessr/articles/runs.md).

- [`hr_options()`](https://elkronos.github.io/harnessr/reference/hr_options.md)
  : Get or set package options
- [`hr_governor()`](https://elkronos.github.io/harnessr/reference/hr_governor.md)
  : Limits on what a run may send
- [`hr_cache()`](https://elkronos.github.io/harnessr/reference/hr_cache.md)
  : A response cache
- [`hr_cache_client()`](https://elkronos.github.io/harnessr/reference/hr_cache_client.md)
  : Attach a cache to a client
- [`hr_cache_stats()`](https://elkronos.github.io/harnessr/reference/hr_cache_stats.md)
  : Cache statistics
- [`hr_cache_clear()`](https://elkronos.github.io/harnessr/reference/hr_cache_clear.md)
  : Delete every entry in a cache
- [`hr_replay_client()`](https://elkronos.github.io/harnessr/reference/hr_replay_client.md)
  : A client that answers from a recorded run

### Compose steps and chains

Build a run from steps, run them in order as one arm, derive a chain by
dropping or replacing a step, list, change and sweep its settings by
path, give a step a skill, and check a step’s output by running a
program. See
[`vignette("compose")`](https://elkronos.github.io/harnessr/articles/compose.md).

- [`hr_step()`](https://elkronos.github.io/harnessr/reference/hr_step.md)
  : A step of a run, with the settings it was built with
- [`hr_chain()`](https://elkronos.github.io/harnessr/reference/hr_chain.md)
  : Run steps in order as one arm
- [`hr_settings()`](https://elkronos.github.io/harnessr/reference/hr_settings.md)
  : List the settings of a step or a chain
- [`hr_set()`](https://elkronos.github.io/harnessr/reference/hr_set.md)
  : Change some settings of a step or a chain
- [`hr_step_command()`](https://elkronos.github.io/harnessr/reference/hr_step_command.md)
  : A step that runs a program
- [`hr_skill()`](https://elkronos.github.io/harnessr/reference/hr_skill.md)
  : Read a skill folder

### Modules and the registry

Register and list modules of any kind, check a module against rules of
your own, and declare what a module’s run costs. See “Registering a
step” in
[`vignette("compose")`](https://elkronos.github.io/harnessr/articles/compose.md).
“Declaring cost” in
[`vignette("extending")`](https://elkronos.github.io/harnessr/articles/extending.md),
a document guide, covers
[`hr_cost()`](https://elkronos.github.io/harnessr/reference/hr_cost.md)
with a reader.

- [`hr_register()`](https://elkronos.github.io/harnessr/reference/hr_register.md)
  : Register a module of any kind
- [`hr_modules()`](https://elkronos.github.io/harnessr/reference/hr_modules.md)
  : List the registered modules of every kind
- [`hr_check_module()`](https://elkronos.github.io/harnessr/reference/hr_check_module.md)
  : Check a module against a set of rules
- [`hr_cost()`](https://elkronos.github.io/harnessr/reference/hr_cost.md)
  : What one run of a module can cost

### Benchmarks

Compare configurations on a labelled reference: arms, sweeps of a
setting, the reference and its splits, scorers, and repeated runs held
to one spending limit. See
[`vignette("evaluate")`](https://elkronos.github.io/harnessr/articles/evaluate.md)
and
[`vignette("compare")`](https://elkronos.github.io/harnessr/articles/compare.md).

- [`hr_benchmark()`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
  [`print(`*`<hr_bench>`*`)`](https://elkronos.github.io/harnessr/reference/hr_benchmark.md)
  : Run arms against a reference
- [`hr_report()`](https://elkronos.github.io/harnessr/reference/hr_report.md)
  [`print(`*`<hr_bench_report>`*`)`](https://elkronos.github.io/harnessr/reference/hr_report.md)
  [`as_json(`*`<hr_bench_report>`*`)`](https://elkronos.github.io/harnessr/reference/hr_report.md)
  : Report a benchmark with intervals
- [`hr_error_correlation()`](https://elkronos.github.io/harnessr/reference/hr_error_correlation.md)
  : Correlated errors between the arms of a benchmark
- [`hr_mdd()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md)
  [`hr_n_needed()`](https://elkronos.github.io/harnessr/reference/hr_mdd.md)
  [`print(`*`<hr_mdd>`*`)`](https://elkronos.github.io/harnessr/reference/hr_mdd.md)
  [`print(`*`<hr_n_needed>`*`)`](https://elkronos.github.io/harnessr/reference/hr_mdd.md)
  : The minimum detectable difference of a paired, clustered design
- [`hr_contrast()`](https://elkronos.github.io/harnessr/reference/hr_contrast.md)
  [`hr_register_contrasts()`](https://elkronos.github.io/harnessr/reference/hr_contrast.md)
  [`print(`*`<hr_contrast>`*`)`](https://elkronos.github.io/harnessr/reference/hr_contrast.md)
  [`print(`*`<hr_contrast_registration>`*`)`](https://elkronos.github.io/harnessr/reference/hr_contrast.md)
  : Non-inferiority contrasts, registered before scoring
- [`hr_drift_check()`](https://elkronos.github.io/harnessr/reference/hr_drift_check.md)
  [`print(`*`<hr_drift_check>`*`)`](https://elkronos.github.io/harnessr/reference/hr_drift_check.md)
  : Check an arm for drift against a frozen benchmark
- [`hr_arm()`](https://elkronos.github.io/harnessr/reference/hr_arm.md)
  : A configuration to compare in a benchmark
- [`hr_sweep()`](https://elkronos.github.io/harnessr/reference/hr_sweep.md)
  : Build one arm per row of a grid of settings
- [`hr_sweep_check()`](https://elkronos.github.io/harnessr/reference/hr_sweep_check.md)
  : Find the settings of a sweep that changed nothing that was sent
- [`hr_reference()`](https://elkronos.github.io/harnessr/reference/hr_reference.md)
  [`hr_reference_add()`](https://elkronos.github.io/harnessr/reference/hr_reference.md)
  : A reference set to score arms against
- [`hr_scorer()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md)
  [`hr_scorer_exact()`](https://elkronos.github.io/harnessr/reference/hr_scorer.md)
  : A rule for scoring an arm's output
- [`hr_assign_splits()`](https://elkronos.github.io/harnessr/reference/hr_assign_splits.md)
  : Assign reference items to splits by cluster

### Judges

A model that chooses between candidates or grades one against a
reference, asked in both orders, validated against blind human labels
before it scores, with its accuracy corrected by those labels. See
[`vignette("evaluate")`](https://elkronos.github.io/harnessr/articles/evaluate.md).

- [`hr_judge()`](https://elkronos.github.io/harnessr/reference/hr_judge.md)
  [`print(`*`<hr_judgement>`*`)`](https://elkronos.github.io/harnessr/reference/hr_judge.md)
  : Judge candidates with a model, in more than one order
- [`hr_judge_config()`](https://elkronos.github.io/harnessr/reference/hr_judge_config.md)
  [`print(`*`<hr_judge_config>`*`)`](https://elkronos.github.io/harnessr/reference/hr_judge_config.md)
  : A judge configuration
- [`hr_judge_validate()`](https://elkronos.github.io/harnessr/reference/hr_judge_validate.md)
  [`hr_judge_valid()`](https://elkronos.github.io/harnessr/reference/hr_judge_validate.md)
  [`print(`*`<hr_judge_validation>`*`)`](https://elkronos.github.io/harnessr/reference/hr_judge_validate.md)
  : Validate a judge against blind human labels
- [`hr_scorer_judge()`](https://elkronos.github.io/harnessr/reference/hr_scorer_judge.md)
  : Score benchmark runs with a validated judge
- [`hr_judge_ppi()`](https://elkronos.github.io/harnessr/reference/hr_judge_ppi.md)
  : Judge-scored accuracy corrected with human labels

### Baselines

Comparisons that use no model: tf-idf features, a cross-fitted
classifier and a simulated active-learning ranker for screening. See
[`vignette("evaluate")`](https://elkronos.github.io/harnessr/articles/evaluate.md).

- [`hr_tfidf()`](https://elkronos.github.io/harnessr/reference/hr_tfidf.md)
  : Tf-idf features from texts
- [`hr_baseline_classifier()`](https://elkronos.github.io/harnessr/reference/hr_baseline_classifier.md)
  [`print(`*`<hr_baseline_classifier>`*`)`](https://elkronos.github.io/harnessr/reference/hr_baseline_classifier.md)
  : Cross-fitted text classifier baseline
- [`hr_baseline_ranker()`](https://elkronos.github.io/harnessr/reference/hr_baseline_ranker.md)
  [`print(`*`<hr_baseline_ranker>`*`)`](https://elkronos.github.io/harnessr/reference/hr_baseline_ranker.md)
  : Active-learning screening baseline

### Signal calibration

The calibration records that measure how well a signal predicts being
right, and the thresholds and policy that decide whether a signal may
gate an action. Nothing gates by default. See
[`vignette("evaluate")`](https://elkronos.github.io/harnessr/articles/evaluate.md).

- [`hr_calibrate_signal()`](https://elkronos.github.io/harnessr/reference/hr_calibrate_signal.md)
  : Calibrate a self-signal against graded items
- [`hr_calibration_valid()`](https://elkronos.github.io/harnessr/reference/hr_calibration_valid.md)
  : Is a calibration record valid for a run?
- [`hr_gate_threshold()`](https://elkronos.github.io/harnessr/reference/hr_gate_threshold.md)
  : Choose a gate threshold by Learn-then-Test
- [`hr_signal_policy()`](https://elkronos.github.io/harnessr/reference/hr_signal_policy.md)
  [`hr_apply_signal()`](https://elkronos.github.io/harnessr/reference/hr_signal_policy.md)
  : What a signal may do, and what happens when it may not

### Statistics

Intervals for proportions, agreement between raters and coders, design-
weighted and prediction-powered estimates, and the test of whether a
model’s labels can stand in for people’s. See
[`vignette("evaluate")`](https://elkronos.github.io/harnessr/articles/evaluate.md).

- [`hr_prop_ci()`](https://elkronos.github.io/harnessr/reference/hr_prop_ci.md)
  : Confidence intervals for binomial proportions
- [`hr_agreement()`](https://elkronos.github.io/harnessr/reference/hr_agreement.md)
  : Agreement between raters, with every measure that should go with it
- [`hr_ht_estimate()`](https://elkronos.github.io/harnessr/reference/hr_ht_estimate.md)
  : Design-weighted estimates from a probability sample
- [`hr_ppi()`](https://elkronos.github.io/harnessr/reference/hr_ppi.md)
  : Prediction-powered inference for a mean
- [`hr_alt_test()`](https://elkronos.github.io/harnessr/reference/hr_alt_test.md)
  : The alternative annotator test

## Documents

The document layer, built on the core: ingest, segment, read, and review
many documents. See
[`vignette("harnessr")`](https://elkronos.github.io/harnessr/articles/harnessr.md)
for a first question.

### Ask a question

One call reads a document and answers a question, and the answer says
what it rests on and whether anything went wrong. See
[`vignette("harnessr")`](https://elkronos.github.io/harnessr/articles/harnessr.md).

- [`answer_document()`](https://elkronos.github.io/harnessr/reference/answer_document.md)
  : Answer a question about a document
- [`gr_answer`](https://elkronos.github.io/harnessr/reference/gr_answer.md)
  : The result of one reading run
- [`is_not_found()`](https://elkronos.github.io/harnessr/reference/is_not_found.md)
  : Did the model report that the document does not contain the answer?
- [`gr_example()`](https://elkronos.github.io/harnessr/reference/gr_example.md)
  : Path to the bundled example document
- [`gr_recipes()`](https://elkronos.github.io/harnessr/reference/gr_recipes.md)
  : Ready-made recipes
- [`gr_recipe()`](https://elkronos.github.io/harnessr/reference/gr_recipe.md)
  : Bind an ingestion, segmentation and reading configuration together
- [`gr_compare()`](https://elkronos.github.io/harnessr/reference/gr_compare.md)
  : Run several recipes over one document and compare them
- [`gr_methods_text()`](https://elkronos.github.io/harnessr/reference/gr_methods_text.md)
  : A methods paragraph from a run's record

### Get text out of files

Extraction, cleaning and a survey of a folder before anything is spent.
See
[`vignette("ingest")`](https://elkronos.github.io/harnessr/articles/ingest.md).

- [`gr_ingest()`](https://elkronos.github.io/harnessr/reference/gr_ingest.md)
  : Ingest a document into cleaned, provenance-bearing text blocks
- [`gr_ingest_spec()`](https://elkronos.github.io/harnessr/reference/gr_ingest_spec.md)
  : Describe an ingestion configuration
- [`gr_document`](https://elkronos.github.io/harnessr/reference/gr_document.md)
  : An ingested document
- [`gr_extractors()`](https://elkronos.github.io/harnessr/reference/gr_extractors.md)
  : List registered extractors
- [`gr_cleaners()`](https://elkronos.github.io/harnessr/reference/gr_cleaners.md)
  : List registered cleaners
- [`gr_clean()`](https://elkronos.github.io/harnessr/reference/gr_clean.md)
  : Run the cleaning pipeline over a character vector
- [`gr_inventory()`](https://elkronos.github.io/harnessr/reference/gr_inventory.md)
  : What is in a folder, before you read any of it
- [`gr_flush_caches()`](https://elkronos.github.io/harnessr/reference/gr_flush_caches.md)
  : Clear the session's document and embedding caches

### Cut documents into chunks

The segmenters, their settings, and the free statistics for comparing
chunkings: size, boundary error against a reference (Pk and WindowDiff)
and retrieval recall. See
[`vignette("segment")`](https://elkronos.github.io/harnessr/articles/segment.md)
and
[`vignette("compare")`](https://elkronos.github.io/harnessr/articles/compare.md).

- [`gr_segment()`](https://elkronos.github.io/harnessr/reference/gr_segment.md)
  : Segment a document into chunks
- [`gr_segment_spec()`](https://elkronos.github.io/harnessr/reference/gr_segment_spec.md)
  : Describe a segmentation configuration
- [`gr_segmenters()`](https://elkronos.github.io/harnessr/reference/gr_segmenters.md)
  : List registered segmentation strategies
- [`gr_chunks`](https://elkronos.github.io/harnessr/reference/gr_chunks.md)
  : A set of document chunks
- [`gr_chunk_stats()`](https://elkronos.github.io/harnessr/reference/gr_chunk_stats.md)
  : Summary statistics for a chunk set
- [`gr_seg_boundaries()`](https://elkronos.github.io/harnessr/reference/gr_seg_boundaries.md)
  : Where a segmentation puts its boundaries, sentence by sentence
- [`gr_seg_pk()`](https://elkronos.github.io/harnessr/reference/gr_seg_pk.md)
  [`gr_seg_windowdiff()`](https://elkronos.github.io/harnessr/reference/gr_seg_pk.md)
  : Pk and WindowDiff: how far a segmentation's boundaries are from a
  reference
- [`gr_seg_recall()`](https://elkronos.github.io/harnessr/reference/gr_seg_recall.md)
  : Retrieval recall at k, per segmenter

### Read the chunks

The reading strategies, the settings that choose and place chunks, the
embedders that rank them, and the check on quoted evidence. See
[`vignette("readers")`](https://elkronos.github.io/harnessr/articles/readers.md).

- [`gr_read()`](https://elkronos.github.io/harnessr/reference/gr_read.md)
  : Read chunks and answer a question
- [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md)
  : Describe a reading configuration
- [`gr_readers()`](https://elkronos.github.io/harnessr/reference/gr_readers.md)
  : List registered reading strategies
- [`gr_reader_signature()`](https://elkronos.github.io/harnessr/reference/gr_reader_signature.md)
  : The traversal signature of a reader
- [`gr_embedders()`](https://elkronos.github.io/harnessr/reference/gr_embedders.md)
  : List registered embedding backends
- [`gr_verify_evidence()`](https://elkronos.github.io/harnessr/reference/gr_verify_evidence.md)
  : Check that quoted evidence really is in the document

### Many documents and literature reviews

One question over many documents, and a review from a search export to
screened studies, an extraction table, a written review and an audit
report, with the screening measured against a hand-screened sample and a
stopping test for prioritised screening. See
[`vignette("review")`](https://elkronos.github.io/harnessr/articles/review.md).

- [`gr_read_many()`](https://elkronos.github.io/harnessr/reference/gr_read_many.md)
  : Ask one question of many documents
- [`gr_protocol()`](https://elkronos.github.io/harnessr/reference/gr_protocol.md)
  : Write down what a review is looking for
- [`gr_protocols()`](https://elkronos.github.io/harnessr/reference/gr_protocols.md)
  : Protocols that ship with the package, and any you have registered
- [`gr_protocol_save()`](https://elkronos.github.io/harnessr/reference/gr_protocol_save.md)
  [`gr_protocol_read()`](https://elkronos.github.io/harnessr/reference/gr_protocol_save.md)
  : Save a protocol to a file, and read one back
- [`gr_register_protocol()`](https://elkronos.github.io/harnessr/reference/gr_register_protocol.md)
  : Register a protocol
- [`gr_search()`](https://elkronos.github.io/harnessr/reference/gr_search.md)
  : Record how the search was run
- [`gr_records()`](https://elkronos.github.io/harnessr/reference/gr_records.md)
  : Read a search export, and say what the search found
- [`gr_search_recall()`](https://elkronos.github.io/harnessr/reference/gr_search_recall.md)
  : Measure a search against papers you already know are relevant
- [`gr_screen()`](https://elkronos.github.io/harnessr/reference/gr_screen.md)
  : Decide which documents a review should read
- [`gr_reference()`](https://elkronos.github.io/harnessr/reference/gr_reference.md)
  : Draw a sample to screen by hand
- [`gr_reference_consensus()`](https://elkronos.github.io/harnessr/reference/gr_reference_consensus.md)
  : Form one decision per document from several reviewers
- [`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md)
  : Measure the screener against a hand-screened sample
- [`gr_screen_sample_size()`](https://elkronos.github.io/harnessr/reference/gr_screen_sample_size.md)
  : How many records to judge by hand to show a recall target
- [`gr_stop_test()`](https://elkronos.github.io/harnessr/reference/gr_stop_test.md)
  [`print(`*`<gr_stop_test>`*`)`](https://elkronos.github.io/harnessr/reference/gr_stop_test.md)
  : Hypergeometric stopping test for prioritised screening
- [`gr_resolve()`](https://elkronos.github.io/harnessr/reference/gr_resolve.md)
  : Record a person's decision on screened records
- [`` `[`( ``*`<gr_reference_frame>`*`)`](https://elkronos.github.io/harnessr/reference/sub-.gr_reference_frame.md)
  : Subsetting a reference frame gives a plain data frame.
- [`gr_fields()`](https://elkronos.github.io/harnessr/reference/gr_fields.md)
  : Build an extraction schema
- [`gr_field()`](https://elkronos.github.io/harnessr/reference/gr_field.md)
  : Describe one field of an extraction schema
- [`gr_extract()`](https://elkronos.github.io/harnessr/reference/gr_extract.md)
  : Extract a typed schema from many documents
- [`gr_extract_agreement()`](https://elkronos.github.io/harnessr/reference/gr_extract_agreement.md)
  : Agreement between two extraction tables, field by field
- [`gr_claims()`](https://elkronos.github.io/harnessr/reference/gr_claims.md)
  : The claims a table of studies supports
- [`gr_outline()`](https://elkronos.github.io/harnessr/reference/gr_outline.md)
  : Derive a review's sections from its claims
- [`gr_outline_pick()`](https://elkronos.github.io/harnessr/reference/gr_outline_pick.md)
  : Choose one of the outlines gr_outline() compared
- [`gr_gaps()`](https://elkronos.github.io/harnessr/reference/gr_gaps.md)
  : What a body of work does not cover
- [`gr_synthesise()`](https://elkronos.github.io/harnessr/reference/gr_synthesise.md)
  : Write a review from an extraction table
- [`gr_recheck()`](https://elkronos.github.io/harnessr/reference/gr_recheck.md)
  : Check and render an edited write-up again
- [`gr_flow()`](https://elkronos.github.io/harnessr/reference/gr_flow.md)
  : Count what happened to every document
- [`gr_audit_report()`](https://elkronos.github.io/harnessr/reference/gr_audit_report.md)
  : Write the run out as an auditable report

### Document arms, steps and references

Document arms and steps for the core benchmarks and chains, question-
answer references, label sheets, and the checks on what a reader keeps.
See
[`vignette("evaluate")`](https://elkronos.github.io/harnessr/articles/evaluate.md)
and
[`vignette("compose")`](https://elkronos.github.io/harnessr/articles/compose.md).

- [`gr_arm()`](https://elkronos.github.io/harnessr/reference/gr_arm.md)
  [`gr_arms()`](https://elkronos.github.io/harnessr/reference/gr_arm.md)
  : A reading recipe as an arm of a benchmark
- [`gr_step()`](https://elkronos.github.io/harnessr/reference/gr_step.md)
  [`gr_step_retrieve()`](https://elkronos.github.io/harnessr/reference/gr_step.md)
  : Built-in steps for composing a run
- [`gr_qa_reference()`](https://elkronos.github.io/harnessr/reference/gr_qa_reference.md)
  : A reference of questions about documents
- [`gr_scorer_answer()`](https://elkronos.github.io/harnessr/reference/gr_scorer_answer.md)
  : Score a reading recipe's answer against acceptable answers
- [`gr_condensation_check()`](https://elkronos.github.io/harnessr/reference/gr_condensation_check.md)
  [`print(`*`<gr_condensation_check>`*`)`](https://elkronos.github.io/harnessr/reference/gr_condensation_check.md)
  [`gr_condensation_summary()`](https://elkronos.github.io/harnessr/reference/gr_condensation_check.md)
  : A test of what a reader keeps as it condenses a document
- [`gr_reverse_text()`](https://elkronos.github.io/harnessr/reference/gr_reverse_text.md)
  : Reverse the order of a text's paragraphs or sentences
- [`gr_label_sheet()`](https://elkronos.github.io/harnessr/reference/gr_label_sheet.md)
  : Write a sheet for people to label
- [`gr_read_labels()`](https://elkronos.github.io/harnessr/reference/gr_read_labels.md)
  : Read a filled label sheet

### Settings of the document stages

The settings of a read, segment or ingest spec, and every setting of
every stage in one table. See
[`vignette("settings")`](https://elkronos.github.io/harnessr/articles/settings.md).

- [`gr_settings()`](https://elkronos.github.io/harnessr/reference/gr_settings.md)
  : The settings of a read, segment or ingest spec
- [`gr_settings_table()`](https://elkronos.github.io/harnessr/reference/gr_settings_table.md)
  : Every setting of every stage

### Extending the document layer

Every document axis is a registry, and an addition is used exactly like
a built-in. Register extractors, cleaners, segmenters, readers and
embedders, build the objects they return, and check them against the
contract. See
[`vignette("extending")`](https://elkronos.github.io/harnessr/articles/extending.md).

- [`gr_register_extractor()`](https://elkronos.github.io/harnessr/reference/gr_register_extractor.md)
  : Register a document extractor

- [`gr_register_cleaner()`](https://elkronos.github.io/harnessr/reference/gr_register_cleaner.md)
  : Register a cleaning step

- [`gr_register_segmenter()`](https://elkronos.github.io/harnessr/reference/gr_register_segmenter.md)
  : Register a segmentation strategy

- [`gr_register_reader()`](https://elkronos.github.io/harnessr/reference/gr_register_reader.md)
  : Register a reading strategy

- [`gr_register_embedder()`](https://elkronos.github.io/harnessr/reference/gr_register_embedder.md)
  : Register an embedding backend

- [`new_chunks()`](https://elkronos.github.io/harnessr/reference/new_chunks.md)
  :

  Build a `gr_chunks`, the object every segmenter must return

- [`new_answer()`](https://elkronos.github.io/harnessr/reference/new_answer.md)
  :

  Build a `gr_answer`, the object every reader must return

- [`gr_check_reader()`](https://elkronos.github.io/harnessr/reference/gr_check_reader.md)
  : Check a reader against the reader contract

- [`gr_check_segmenter()`](https://elkronos.github.io/harnessr/reference/gr_check_segmenter.md)
  : Check a segmenter against the segmenter contract
