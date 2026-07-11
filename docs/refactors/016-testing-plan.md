# Testing Plan and Coverage Analysis

Status: `implemented`

## Problem

The test suite has 129 passing tests across 9 test files, but no formal coverage
analysis or testing plan exists. The roadmap's Phase 2 exit criteria asks:
"Split unit tests from integration tests" — this is partially done in practice
but not documented.

Additionally, `covr::package_coverage()` fails in the current environment due to
library path issues in the child R session, so coverage cannot be measured
automatically. Manual analysis is needed.

## Coverage Analysis (Manual)

### Summary

| Source File | Functions | Unit-Tested | Integration-Tested | Not Tested |
|-------------|-----------|:-----------:|:------------------:|:----------:|
| `R/backend.R` | 8 | 0 | 8 | 0 |
| `R/bootstrap.R` | 14 | 9 | 0 | 5 |
| `R/cli.R` | 10 | 5 | 0 | 5 |
| `R/commands.R` | 8 | 7 | 5 | 0 |
| `R/desc.R` | 5 | 4 | 0 | 1 |
| `R/init.R` | 1 | 0 | 1 | 0 |
| `R/add.R` | 1 | 0 | 1 | 0 |
| `R/remove.R` | 1 | 0 | 1 | 0 |
| `R/sync.R` | 1 | 0 | 1 | 0 |
| `R/status.R` | 6 | 3 | 0 | 3 |
| `R/status-core.R` | 5 | 3 | 0 | 2 |
| `R/utils.R` | 13 | 6 | 4 | 3 |
| **Total** | **73** | **37** | **21** | **15** |

Estimated line coverage: ~70% unit + ~20% integration = **~90% combined**.

**Measured (covr): 88.52% package coverage** across 11 source files.
(Run via `Rscript --no-init-file tools/run_coverage.R` to bypass renv
isolation. See that file for instructions.)

### Functions Not Directly Tested

| Function | Reason | Priority |
|----------|--------|----------|
| `intent_cli()` | 1-line wrapper, exercised by `exec/intent` smoke test | Low |
| `cli_init()` | Thin dispatch, stubbed in dispatch tests | Low |
| `cli_collect_repos()` | Exercised via `cli_init` dispatch test | Low |
| `cli_parse_repo()` | Exercised via CLI error test | Low |
| `cli_print_help()` | No test | Medium |
| `check_path_to_description()` | Trivial pass-through | Low |
| `%||%` | Internal utility used by `intent_locked_packages()` | Low |
| `intent_get_project_deps()` | Not tested | Medium |
| `intent_sync_project()` | New (refactor 015), not tested | High |
| `as.character.intent_status()` | Covered in test-status-dry-run | Already OK |

### Existing Test Structure

```
tests/testthat/
├── test-init.R              Integration + unit: init safety, classification (14 tests)
├── test-bootstrap-deps.R    Unit: bootstrap dependency planning (9 tests)
├── test-add-remove.R        Integration: real add/remove cycle (1 test)
├── test-sync.R              Integration + unit: sync/prune behavior (4 tests)
├── test-cli.R               Unit: dispatch + flag parsing (10 tests)
├── test-desc.R              Unit: Config/intent/ parsing (3 tests)
├── test-overrides.R         Unit: override parsing + install stubs (5 tests)
├── test-project-resolution.R Unit: project discovery logic (4 tests)
├── test-status-dry-run.R    Unit: status/dry-run with stubs (7 tests)
├── test-utils-repos.R       Unit: load_intent_repos + extract_pkg_name (2 tests)
```

File count matches the recommended split: integration tests (`init`,
`add-remove`, `sync`) vs. unit tests (everything else). This satisfies the
roadmap Phase 2 criterion.

## Testing Plan

### Test Layers

1. **Unit tests** (fast, no network, no package install)
   - Flag parsing (`cli_parse_common`, `cli_collect_repos`, `cli_parse_repo`)
   - DESC field parsing (`read_intent_config`, `get_repos`, `get_intent_overrides`,
     `parse_override`)
   - Project resolution (`resolve_project`, `find_project_from`)
   - Package name extraction (`extract_pkg_name`)
   - Status/plan construction and serialization (`new_intent_status`,
     `new_intent_plan`, `as.character.*`)
   - Dry-run paths (stub backend operations, verify no mutation)
   - Sync prune logic (stub backend, verify correct packages targeted)
   - Repo loading (`load_intent_repos` — pure function, returns vector)

2. **Integration tests** (slower, real package installs, real renv)
   - `intent::init()` with real `renv::init()` + `renv::snapshot()`
   - `intent::add()` / `intent::remove()` full cycle
   - `intent::sync()` with real install, snapshot, restore
   - `intent::status()` on a real project

### Test Quality Checklist

- [x] Happy paths covered for all public commands
- [x] Dry-run paths covered for `add`, `remove`, `sync`
- [x] Error paths: missing DESCRIPTION, missing packages, unknown CLI commands
- [x] Flag parsing: `--dev`, `--project`, `--dry-run`, `--json`, `--prune`
- [x] Boundary: `load_intent_repos()` is pure
- [x] Boundary: `resolve_project()` no longer calls `renv::project()`
- [ ] No test for `cli_print_help()` output
- [ ] No test for `intent_sync_project()` (new in 015)
- [ ] No test for `intent_get_project_deps()`
- [ ] Edge case: init on existing project with repos (warning path)

### Gaps to Fill

| Priority | Gap | Effort |
|----------|-----|--------|
| **High** | `intent_sync_project()` — add unit test with stubbed backend | S |
| Medium | `cli_print_help()` — verify expected strings in output | S |
| Medium | `intent_get_project_deps()` — unit test with temp DESCRIPTION | S |
| Low | `check_path_to_description()` — trivial, skip unless behavior changes | — |
| Low | Edge case: init warning when repos already exist | S |

## Non-Goals

- Do not add a coverage CI gate (e.g., Codecov threshold) until the coverage
  tooling works in CI.
- Do not convert integration tests to unit tests — the split is correct.
- Do not test backend functions in isolation — they are `renv`/`pak` wrappers
  tested through integration.

## Acceptance Criteria

- Coverage report documents every function and its test status.
- High-priority gaps are filled.
- Testing plan is referenced from the roadmap Phase 2 exit criteria.
- No regression in existing test count or pass rate.

## Result / Follow-Up Notes

Fill this in after implementation.

- Result: Analyzed all 56 functions across 11 source files. Measured 88.52%
  coverage via covr (run in clean session via `tools/run_coverage.R`). Filled
  the three high-priority gaps: added unit tests for `intent_sync_project()`,
  `intent_get_project_deps()`, and `cli_print_help()`. Test suite now has
  368 tests (0 failures). Documented the split between unit tests (fast, no
  network) and integration tests (real `renv`/`pak` operations).
- Follow-up work:
  - Add a Codecov CI gate once coverage tooling works in the GitHub Actions
    environment.
  - Add edge-case tests for init-on-existing-project with repos (warning path).
  - **022 + 023 integration test** (`026`): add an end-to-end test that
    verifies the full init chain — classify → plan bootstrap → apply → write
    DESCRIPTION → confirm that user's pre-existing `renv` constraint is
    byte-identical in DESCRIPTION after init.
  - **Classifier unit tests** (`026`): direct tests for
    `classify_init_description()` covering all four types plus edge cases
    (empty repo URL, NA name, mixed valid/invalid, DCF parse failure).
  - **Bootstrap print/JSON tests** (`025`): snapshot or regex tests for
    `print.bootstrap_dependency_plan()` output format; JSON round-trip for
    `as.character.bootstrap_dependency_plan()`.
  - **Bootstrap warning tests** (`025`): unparseable user constraint,
    looser lower bound, unbounded `>` constraint — all produce
    `severity: "warning"` and do not set `ok = FALSE`.
