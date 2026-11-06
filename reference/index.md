# Package index

## Ask a question

Start here. One call reads a document and answers a question, and the
answer says what it rests on and whether anything went wrong. See
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

## Connect to a model

Clients for OpenAI-compatible endpoints, any provider ellmer supports,
any function you write, and an offline stand-in for practice and tests.
See
[`vignette("harnessr")`](https://elkronos.github.io/harnessr/articles/harnessr.md)
and the README.

- [`gr_client()`](https://elkronos.github.io/harnessr/reference/gr_client.md)
  : Construct a model client
- [`gr_api_key()`](https://elkronos.github.io/harnessr/reference/gr_api_key.md)
  : Resolve the API key
- [`gr_ellmer_client()`](https://elkronos.github.io/harnessr/reference/gr_ellmer_client.md)
  : Read documents through an ellmer chat
- [`gr_backend_client()`](https://elkronos.github.io/harnessr/reference/gr_backend_client.md)
  : Use any function as the model transport
- [`gr_mock_client()`](https://elkronos.github.io/harnessr/reference/gr_mock_client.md)
  : A deterministic offline client for tests, demos and dry runs
- [`gr_call()`](https://elkronos.github.io/harnessr/reference/gr_call.md)
  : Call a model
- [`gr_result`](https://elkronos.github.io/harnessr/reference/gr_result.md)
  : The result of one model call
- [`gr_models()`](https://elkronos.github.io/harnessr/reference/gr_models.md)
  : List every known model
- [`gr_model_info()`](https://elkronos.github.io/harnessr/reference/gr_model_info.md)
  : Look up a model's capabilities
- [`gr_model_limits()`](https://elkronos.github.io/harnessr/reference/gr_model_limits.md)
  : Context and output limits for a model
- [`gr_register_model()`](https://elkronos.github.io/harnessr/reference/gr_register_model.md)
  : Register a model (or override a built-in entry)

## Get text out of files

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

## Cut documents into chunks

The segmenters, their settings, and the free statistics for comparing
chunkings. See
[`vignette("segment")`](https://elkronos.github.io/harnessr/articles/segment.md).

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

## Read the chunks

The reading strategies, the settings that choose and place chunks, and
the check on quoted evidence. See
[`vignette("readers")`](https://elkronos.github.io/harnessr/articles/readers.md).

- [`gr_read()`](https://elkronos.github.io/harnessr/reference/gr_read.md)
  : Read chunks and answer a question
- [`gr_read_spec()`](https://elkronos.github.io/harnessr/reference/gr_read_spec.md)
  : Describe a reading configuration
- [`gr_readers()`](https://elkronos.github.io/harnessr/reference/gr_readers.md)
  : List registered reading strategies
- [`gr_reader_signature()`](https://elkronos.github.io/harnessr/reference/gr_reader_signature.md)
  : The traversal signature of a reader
- [`gr_embed()`](https://elkronos.github.io/harnessr/reference/gr_embed.md)
  : Embed texts
- [`gr_embedders()`](https://elkronos.github.io/harnessr/reference/gr_embedders.md)
  : List registered embedding backends
- [`gr_verify_evidence()`](https://elkronos.github.io/harnessr/reference/gr_verify_evidence.md)
  : Check that quoted evidence really is in the document

## Many documents and literature reviews

One question over many documents, and a review from a search export to
screened studies, an extraction table, a written review and an audit
report, with the screening measured against a hand-screened sample. See
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
- [`gr_screen()`](https://elkronos.github.io/harnessr/reference/gr_screen.md)
  : Decide which documents a review should read
- [`gr_reference()`](https://elkronos.github.io/harnessr/reference/gr_reference.md)
  : Draw a sample to screen by hand
- [`gr_calibrate()`](https://elkronos.github.io/harnessr/reference/gr_calibrate.md)
  : Measure the screener against a hand-screened sample
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
- [`gr_flow()`](https://elkronos.github.io/harnessr/reference/gr_flow.md)
  : Count what happened to every document
- [`gr_audit_report()`](https://elkronos.github.io/harnessr/reference/gr_audit_report.md)
  : Write the run out as an auditable report

## Cost, limits and tracing

Settings and spending limits, token counts and cost estimates, and the
trace every run records. See
[`vignette("runs")`](https://elkronos.github.io/harnessr/articles/runs.md).

- [`gr_options()`](https://elkronos.github.io/harnessr/reference/gr_options.md)
  : Get or set package options

- [`hr_governor()`](https://elkronos.github.io/harnessr/reference/hr_governor.md)
  : Limits on what a run may send

- [`gr_estimate_cost()`](https://elkronos.github.io/harnessr/reference/gr_estimate_cost.md)
  : Estimate the USD cost of a set of calls

- [`gr_count_tokens()`](https://elkronos.github.io/harnessr/reference/gr_count_tokens.md)
  : Count tokens in text

- [`gr_tokenizer()`](https://elkronos.github.io/harnessr/reference/gr_tokenizer.md)
  : The active tokenizer

- [`gr_set_tokenizer()`](https://elkronos.github.io/harnessr/reference/gr_set_tokenizer.md)
  : Register or inspect the active tokenizer

- [`gr_truncate_tokens()`](https://elkronos.github.io/harnessr/reference/gr_truncate_tokens.md)
  :

  Truncate text to at most `n` tokens

- [`gr_budget()`](https://elkronos.github.io/harnessr/reference/gr_budget.md)
  : Compute a usable input-token budget for one model call

- [`gr_trace()`](https://elkronos.github.io/harnessr/reference/gr_trace.md)
  [`as.data.frame(`*`<gr_trace>`*`)`](https://elkronos.github.io/harnessr/reference/gr_trace.md)
  : Create a run trace

- [`gr_trace_summary()`](https://elkronos.github.io/harnessr/reference/gr_trace_summary.md)
  : Summarise a trace

- [`gr_trace_cost()`](https://elkronos.github.io/harnessr/reference/gr_trace_cost.md)
  : What a run actually cost

- [`gr_trace_save()`](https://elkronos.github.io/harnessr/reference/gr_trace_save.md)
  : Save a trace to a file

- [`as_json()`](https://elkronos.github.io/harnessr/reference/as_json.md)
  : Serialise an object to JSON

## Caching and replaying runs

Paying for a request once, and replaying a recorded run without a model.
See
[`vignette("runs")`](https://elkronos.github.io/harnessr/articles/runs.md).

- [`gr_cache()`](https://elkronos.github.io/harnessr/reference/gr_cache.md)
  : A response cache
- [`gr_cache_client()`](https://elkronos.github.io/harnessr/reference/gr_cache_client.md)
  : Attach a cache to a client
- [`gr_cache_stats()`](https://elkronos.github.io/harnessr/reference/gr_cache_stats.md)
  : Cache statistics
- [`gr_cache_clear()`](https://elkronos.github.io/harnessr/reference/gr_cache_clear.md)
  : Delete every entry in a cache
- [`gr_flush_caches()`](https://elkronos.github.io/harnessr/reference/gr_flush_caches.md)
  : Clear the session's document and embedding caches
- [`gr_replay_client()`](https://elkronos.github.io/harnessr/reference/gr_replay_client.md)
  : A client that answers from a recorded run

## Extending harnessr

Every axis is a registry, and an addition is used exactly like a
built-in. See
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

- [`hr_cost()`](https://elkronos.github.io/harnessr/reference/hr_cost.md)
  : What one run of a module can cost

- [`hr_schema()`](https://elkronos.github.io/harnessr/reference/hr_schema.md)
  : Collect parameters into a schema

- [`hr_param()`](https://elkronos.github.io/harnessr/reference/hr_param.md)
  : Declare one parameter of a module or spec

- [`hr_validate()`](https://elkronos.github.io/harnessr/reference/hr_validate.md)
  : Validate and resolve settings against a schema

- [`hr_check_module()`](https://elkronos.github.io/harnessr/reference/hr_check_module.md)
  : Check a module against a set of rules

- [`gr_check_reader()`](https://elkronos.github.io/harnessr/reference/gr_check_reader.md)
  : Check a reader against the reader contract

- [`gr_check_segmenter()`](https://elkronos.github.io/harnessr/reference/gr_check_segmenter.md)
  : Check a segmenter against the segmenter contract

## Superseded

The entry points of the first version, and the old name of
[`gr_example()`](https://elkronos.github.io/harnessr/reference/gr_example.md).
They still work and warn once; new code should use
[`answer_document()`](https://elkronos.github.io/harnessr/reference/answer_document.md),
[`gr_ingest()`](https://elkronos.github.io/harnessr/reference/gr_ingest.md),
[`gr_segment()`](https://elkronos.github.io/harnessr/reference/gr_segment.md)
and
[`gr_example()`](https://elkronos.github.io/harnessr/reference/gr_example.md).
The README’s “Migrating from v1” section maps each one.

- [`answer_question()`](https://elkronos.github.io/harnessr/reference/answer_question.md)
  : Deprecated: answer a question using v1 mode names
- [`parse_text()`](https://elkronos.github.io/harnessr/reference/parse_text.md)
  : Deprecated: parse a document into text chunks
- [`gpt_read_chunked()`](https://elkronos.github.io/harnessr/reference/gpt_read_chunked.md)
  : Deprecated: chunk-by-chunk reading
- [`gpt_read_hierarchical()`](https://elkronos.github.io/harnessr/reference/gpt_read_hierarchical.md)
  : Deprecated: hierarchical reading
- [`gpt_read_multipass()`](https://elkronos.github.io/harnessr/reference/gpt_read_multipass.md)
  : Deprecated: multi-pass reading
- [`gpt_read_retrieval()`](https://elkronos.github.io/harnessr/reference/gpt_read_retrieval.md)
  : Deprecated: evidence-extraction reading
- [`readgpt_example()`](https://elkronos.github.io/harnessr/reference/readgpt_example.md)
  : Deprecated: path to the bundled example document
