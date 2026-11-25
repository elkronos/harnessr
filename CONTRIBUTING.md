# Contributing to harnessr

Bug reports, questions and pull requests are welcome at
<https://github.com/elkronos/harnessr/issues>. For a bug, a short script that
shows it with `gr_mock_client()` is the most useful thing you can send: it
runs anywhere, with no key and no cost.

## Working on harnessr

### Running the tests

From the repository root:

```bash
bash run-tests.sh            # install what is missing, install the package, run the suite
bash run-tests.sh --check    # a full R CMD check instead
```

Every test uses an offline mock client, so no key is needed and no request
leaves your machine. The parallel tests start worker processes, and each
worker loads the installed harnessr, not your source tree. `run-tests.sh`
installs the package first; when you run a test file yourself, reinstall
with `R CMD INSTALL .` before it, or the workers run the old code. The tests
workflow on GitHub runs the same suite, then runs every R block of the
README, knits every guide with no key and no network, and fails if any of
that left a new or changed file in the repository that `git status`
reports. Files `.gitignore` names are not reported, so output that matches
one of its patterns (`docs/`, `*.Rout`, `readgpt_history_*.json`,
`sim-results/`) passes that check unseen.

Three scripts rewrite the fixtures the tests compare against. Run them from
the repository root, and only when you mean to change what they record:

| Script | What it rewrites |
|---|---|
| `Rscript dev/record-golden.R` | the golden records in `tests/testthat/fixtures/golden/` and `fixtures/golden-heuristics/` |
| `Rscript dev/record-layers.R` | `fixtures/boundary/layers.csv`, the layer of every object in `R/` |
| `Rscript dev/record-doc-internal.R` | `fixtures/boundary/doc-uses-internal.csv`, the core internals the document layer uses |

`Rscript dev/ci/pr-checks.R <mode> origin/main HEAD` runs a pull request
check locally; the modes are `tests`, `deps`, `lint`, `namespace` and
`commits`.

### Checks on GitHub

A pull request runs these workflows:

| Workflow | Check names | What it runs |
|---|---|---|
| `R-CMD-check.yaml` | `macos-latest (R release)`, `ubuntu-latest (R release)`, `ubuntu-latest (R oldrel-1)` | `R CMD check` with hard dependencies; a warning fails it |
| `tests.yaml` | `tests` | the suite with `future`, `future.apply`, `ellmer` and `xml2` installed, from the source tree, then the README and guide checks described above |
| `pr-checks.yaml` | `pull request checks` | the `tests`, `deps`, `namespace` and `commits` modes, one step each; every step runs even when an earlier one fails, and the step name says which check failed |
| `pr-lint.yaml` | `lint changed R files` | the `lint` mode |
| `pkgdown.yaml` | `pkgdown` | builds the site without publishing it, only when the pull request changes a file the site is built from (the list is in the workflow) |

Adding or removing a label reruns `pr-checks.yaml`, so a label added after
review turns its check green without a new push. Lint reads no label, so a
label change does not rerun it; a push or a reopen does. A new push to a pull request cancels the older runs
of the same workflow. On `main`, each merge gets its own run of
`R-CMD-check.yaml` and `tests.yaml`, and `pkgdown.yaml` builds and publishes
the site from the newest push to `main`.

`pr-checks.yaml` used to run five checks: `no weakened tests`,
`no unreviewed dependencies`, `lint changed R files`,
`no unreviewed export removals` and `no attribution in commit messages`.
Four of them are now steps of `pull request checks`, and
`lint changed R files` comes from `pr-lint.yaml`. A branch rule or ruleset
that requires the old names needs updating. Do not require `pkgdown`: a
pull request that changes none of its files never starts it, and a required
check that never starts stays pending.

### What must stay true

- **Requests and cache keys do not move at the defaults.** With every
  setting at its default, the package sends byte for byte the requests it
  sent before your change and computes the same cache and replay keys, so
  a cache someone has built and a recording they made keep working. A new
  setting is left out of a spec while it is at its default for this reason.
  The golden records check it.
- **The golden fixtures are the record of what the package does.**
  `test-golden.R` and `test-golden-heuristics.R` compare every recipe,
  reader and review stage, the exported API, the numeral parser and the PDF
  layout pass with `fixtures/golden/` and `fixtures/golden-heuristics/`.
  When a change in behaviour is intended, rerun `dev/record-golden.R` and
  say in the commit message what changed and why. Never rerun it to make a
  failure go away that you cannot explain.
- **The core does not reach into the document layer.** Files named
  `R/core-*.R` are the general core; `R/doc-*.R` are the document layer. A
  core function may not call or read anything a document file defines,
  except the crossings in `fixtures/boundary/allowed.csv`. The document
  layer should use the core through its exports; the internals it still
  uses are listed in `fixtures/boundary/doc-uses-internal.csv`. Both lists
  may only shrink. `test-boundary.R` and `test-doc-internal.R` check this.
  Each exported core `hr_` function needs a caller in the document layer or
  the tests, listed in `NOTES-primitives.md`. A change to what a module must
  do changes the contract version; see `CONTRACT.md`.
- **Results go outside the package.** Tests, guides and help page
  examples write to `tempdir()` or a directory the user chose, never into
  the repository. Live runs and their results are kept outside the
  repository too. Two README examples are the exception:
  `gr_audit_report("answer.html", ...)` and `gr_audit_report("audit.html", ...)`
  write to the working directory, so `.gitignore` names `/answer.html` and
  `/audit.html`.

### What harnessr does not do

These keep the core small. A pull request that adds one of them will be
asked to live in a separate package instead.

- No domain types in the core: documents, chunks and pages belong to the
  document layer.
- No sandboxing, file editing, patch application, git or process isolation.
  A user-written command step is allowed; the package never chooses,
  generates or isolates commands.
- No multi-agent orchestration or debate, and no model choosing its own
  tools or skills. A person composes the steps.
- No general workflow engine: stages run as a chain of hand-offs.
- No model may register modules, or change evaluation sets, references,
  gates, budgets or ledgers.
- No confidence from log probabilities, and no early stopping on them.
- No model-controlled condensing or token-level prompt compression in the
  defaults.
- No long-lived memory engine.
- No new default that makes extra calls, samples, stages, judges or
  commands. A new module is opt-in until a benchmark shows it pays at the
  same cost.
- No vector database and no set of provider SDKs: the built-in HTTP client,
  a backend function and the ellmer adapter are the transports.
- No unvalidated model judge as the measure of accuracy or faithfulness.

### Labels on pull requests

The pull request checks fail on some changes until a maintainer has
reviewed them and added a label:

| Label | What it allows |
|---|---|
| `tests-reviewed` | removing an `expect_*()` call, adding a `skip()`, or adding a row to `allowed.csv` or `doc-uses-internal.csv` |
| `deps-reviewed` | adding a package to `DESCRIPTION` (it must be on CRAN either way) |
| `exports-reviewed` | removing an export from `NAMESPACE`; list it under "## Removed" in `NEWS.md` with what to use instead |

No label lets a commit message carry a `Co-Authored-By` trailer, a link to
a chat or session, or a "Generated with" line. Reword the commit instead.
This applies to commit messages only, not to the files.

### When a test disagrees with your change

Report a conflicting test, never edit it to pass. A test that fails after
your change is either a bug your change introduced or a test that encodes a
decision your change reverses. Either way, say which test and why in the
pull request, and let the review decide. Weakening a test, skipping it or
rewriting its expected value to match new output hides exactly the change
the test exists to show.
