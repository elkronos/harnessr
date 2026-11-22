# The module contract

A module is a function the package runs through a registry: an extractor,
cleaner, segmenter, reader or embedder, or a module of your own. The module
contract is what the core requires of a module and what a conformance check
reports about it. Its version is what `hr_contract_version()` returns
(internal, in `R/core-registry-contract.R`):

**Current version: 0.1**

## What the version covers

1. **Kinds of module.** A layer tells the core about a kind with
   `hr_register_kind(name, ...)`. The core keeps `name` and whatever else is
   given (the document layer gives `registry`, the name of the registry its
   modules are kept in). The document layer registers five kinds at load:
   `extractor`, `cleaner`, `segmenter`, `reader` and `embedder`.
2. **The conformance report.** `hr_check_module(fn, run, rules, kind, name)`
   returns an `hr_conformance` data frame with the columns `rule`, `ok`
   (`TRUE`, `FALSE`, or `NA` for a rule not checked) and `detail` (one
   string, `""` when there is nothing to say), and the attributes `kind`,
   `name`, `contract` (this version) and `warnings`. The first two rows are
   always `is_function` and `runs`. A rule returns `TRUE`, `FALSE` or `NA`,
   or a list with `ok` and `detail`.
3. **The reader rules** (`gr_check_reader()`): `answer_class`,
   `answer_fields` (the answer has `answer`, `reader`, `question`,
   `chunks_used`, `partial`, `notes`, `trace`, `warnings` and `signature`,
   and `partial` is one `TRUE` or `FALSE`), `answer_text`, `evidence`,
   `chunks_used`, `calls_declared` and `calls_within_cost`.
4. **The segmenter rules** (`gr_check_segmenter()`): `chunks_class`,
   `chunk_columns` (`chunk_id`, `text`, `tokens`, `chars`, `page`,
   `section` and `block_id`), `chunk_text`, `chunk_ids`, `within_cap` and
   `calls_declared`.

The version is recorded where a result depends on it: in the `contract`
attribute of every conformance report, and in the `contract_version` field
of the key of a signal calibration (`hr_calibrate_signal()`), which is
filled with the current version when the key leaves it out.

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

### Unreleased

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
