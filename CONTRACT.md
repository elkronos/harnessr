# The module contract

A module is a function or object the package runs through a registry: an
extractor, cleaner, segmenter, reader, embedder, protocol or step, or a
module of your own. The module
contract is what the core requires of a module and what a conformance check
reports about it. Its version is what `hr_contract_version()` returns
(internal, in `R/core-registry-contract.R`):

**Current version: 0.2**

## What the version covers

1. **Kinds of module.** A layer tells the core about a kind with
   `hr_register_kind(name, ...)`. The core keeps `name` and whatever else is
   given (the document layer gives `registry`, the name of the registry its
   modules are kept in). The document layer registers six kinds at load:
   `extractor`, `cleaner`, `segmenter`, `reader`, `embedder` and
   `protocol`. The core then registers its own kind, `step`, whose
   registry it keeps itself. Models are not a kind: the model registry
   stays outside the module registry.
2. **The entry fields.** An entry registered with `hr_register()` has
   `version` and `contract`: the version you give (for a step, the step's
   own version when you give none) and the contract version the package
   implements. An entry registered through a kind's own function, such as
   `gr_register_reader()`, has neither, and every listing shows `NA` for
   it; its conformance check stays advisory. Each listing (`gr_readers()`, `gr_segmenters()`,
   `gr_cleaners()`, `gr_extractors()`, `gr_embedders()`, `gr_protocols()`
   and `hr_modules()`) shows them as its last two columns, `version` then
   `contract`, and keeps its other columns, their types, their order and
   its row names.
3. **The conformance report.** `hr_check_module(fn, run, rules, kind, name)`
   returns an `hr_conformance` data frame with the columns `rule`, `ok`
   (`TRUE`, `FALSE`, or `NA` for a rule not checked) and `detail` (one
   string, `""` when there is nothing to say), and the attributes `kind`,
   `name`, `contract` (this version) and `warnings`. The first two rows are
   always `is_function` and `runs`. A rule returns `TRUE`, `FALSE` or `NA`,
   or a list with `ok` and `detail`.
4. **The reader rules** (`gr_check_reader()`): `answer_class`,
   `answer_fields` (the answer has `answer`, `reader`, `question`,
   `chunks_used`, `partial`, `notes`, `trace`, `warnings` and `signature`,
   and `partial` is one `TRUE` or `FALSE`), `answer_text`, `evidence`,
   `chunks_used`, `calls_declared` and `calls_within_cost`.
5. **The segmenter rules** (`gr_check_segmenter()`): `chunks_class`,
   `chunk_columns` (`chunk_id`, `text`, `tokens`, `chars`, `page`,
   `section` and `block_id`), `chunk_text`, `chunk_ids`, `within_cap` and
   `calls_declared`.
6. **The rules for the other kinds** (internal; the conformance tests run
   them on every registered module): extractor `blocks_shape`,
   `block_text`, `block_columns`, `unread_pages`; cleaner `text_class`,
   `keeps_text`, `logged`, `deterministic`; embedder `matrix_shape`,
   `finite`, `unit_rows`, `source`, `deterministic`; protocol
   `protocol_class`, `name_matches`, `question`, `criteria`, `fields`,
   `outline`, `round_trip`; step `returns_value`, `declared_output`,
   `held_attached`; and, for a reader under a call cap,
   `within_max_calls`, `stops_cleanly`, `partial_when_capped`.

The version is recorded where a result depends on it: in the `contract`
attribute of every conformance report, and in the `contract` field of each
module registered with `hr_register()`.

Signal calibrations keep a contract of their own. The `contract_version`
field of a calibration key (`hr_calibrate_signal()`) is filled with the
signal contract version when the key leaves it out, and that version stays
at **0.1** (internal, `.hr_signal_contract` in
`R/core-signal-calibrate.R`). A record you saved under 0.1 stays valid, and
its key stays byte-identical, when the module contract moves.

## Rules for changing it

- Any change to the fields above (a kind added or removed, a column or
  attribute of the report, a rule added, removed, renamed or made stricter)
  bumps the minor version: 0.1 to 0.2. A change that touches none of them,
  such as a clearer `detail` message, does not.
- Each bump gets an entry below that lists every field that changed.
- The version is pinned in `tests/testthat/test-core-kinds.R`, and
  `tests/testthat/test-contract-files.R` checks that the current version at
  the top of this file is the one `hr_contract_version()` returns. Change
  all three together.
- Once the conformance checks have passed for two releases in a row, the
  fields are frozen, and 1.0 follows.

## Changelog

### 0.2 (2026-11-24)

- Kinds: `protocol` (registry `protocols`) and `step` (registry `steps`,
  kept by the core) join the five kinds of 0.1. `hr_register()` and
  `hr_modules()` cover both, and each kind has a conformance check.
- Entry fields: `version` and `contract`, `NA` for an entry registered
  through a kind's own function.
- Listings: the six `gr_*()` listings and `hr_modules()` end with `version`
  and `contract`. No other column changed.
- Signal calibrations: their `contract_version` default is the signal
  contract, frozen at 0.1, instead of this version.
- Rules: the extractor, cleaner, embedder, protocol, step and call cap
  rules listed above, added on 2026-11-24 without a bump, now belong to the
  contract.
- The conformance report, the reader rules and the segmenter rules are
  unchanged; a report's `contract` attribute now says 0.2.

### Earlier changes under 0.1

No field changes; the version stays 0.1. Checked on 2026-11-22 against the
commit that added the conformance checks (b40139e): `hr_check_module()`,
the report, `hr_register_kind()` and the reader and segmenter rules are
unchanged since. The calibration key started recording `contract_version`
in this period; that records the version and does not change the contract.

### 0.1 (2026-11-05)

The first version, with the core's own state and registry of kinds
(2184208). The conformance report and the reader and segmenter rules
followed on 2026-11-06 (b40139e), under the same version. All fields above
as listed.
