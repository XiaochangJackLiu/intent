# Init Classification Hardening

Status: `implemented`

## Problem

`classify_init_description()` is the single gatekeeper that decides whether
`intent::init()` proceeds or stops. It was introduced in `022` as a read-only
classifier returning one of four types (`intent_manifest`, `non_intent_manifest`,
`missing_manifest`, `invalid_manifest`). However:

1. **No direct unit tests.** The classifier is tested only indirectly through
   `cmd_init()` stubs. Edge cases — empty repo URL values, `NA` repository
   names, partially valid multi-repo configs, DCF parse failures in
   `read_intent_config()` — have no targeted coverage.

2. **Classification scope mismatch.** `stop_for_unsafe_init()` tells users with
   a `non_intent_manifest` to "ensure Imports and Suggests list the direct
   dependencies to manage," but the classifier only checks
   `Config/intent/repos/*`. Either the message or the check is wrong.

3. **No fallthrough protection.** The `switch()` in `stop_for_unsafe_init()`
   has cases for all four known types but no default branch. A future
   classification type would silently pass.

4. **Side-effect ordering.** `dir.create()` in `cmd_init()` (`R/commands.R:17-19`)
   runs after classification and the safety gate, but sits outside any branch.
   A future code insertion between these lines could create a directory before
   init is refused.

5. **Duplicate file check.** `cmd_init()` checks `file.exists(desc_path)` at
   line 28, but the classifier already made the same check 11 lines earlier.
   This is redundant and opens a TOCTOU window.

6. **No user-facing classification API.** Users cannot inspect how their
   project will be classified before running `init()`. The design doc in `022`
   positions the classifier as a reusable component, but it is entirely hidden.

## Goal

1. Add direct unit tests for `classify_init_description()` covering all four
   classification types plus edge cases.
2. Align the classification check with the error messages, or vice versa.
3. Add a default fallthrough branch to `stop_for_unsafe_init()`.
4. Move `dir.create()` inside the safe-init branch.
5. Eliminate the redundant `file.exists(desc_path)` check in `cmd_init()`.
6. Expose classification as a user-inspectable result (optional — evaluate
   cost/benefit).

## Non-Goals

- Do not change the init decision matrix behaviour.
- Do not add automatic migration or dependency inference.
- Do not change `add()`, `remove()`, `sync()`, `status()`, or `verify()`.
- Do not export `classify_init_description()` as a stable public API unless
  the API design is reviewed separately.

## Proposed Design

### Direct Unit Tests for `classify_init_description()`

| Test Case | Expected `type` |
|-----------|----------------|
| Valid DESCRIPTION with `Config/intent/repos/CRAN: https://example.com` | `intent_manifest` |
| Valid DESCRIPTION with multiple named repos | `intent_manifest` |
| DESCRIPTION with `Config/intent/repos/` but empty URL value | `non_intent_manifest` |
| DESCRIPTION with `Config/intent/repos/` but empty name (e.g. `Config/intent/repos/: url`) | `non_intent_manifest` |
| DESCRIPTION with only `Package` and `Version` — no intent config | `non_intent_manifest` |
| DESCRIPTION that triggers `read_intent_config()` parse error | `non_intent_manifest` (or a new type — see below) |
| `DESCRIPTION` does not exist | `missing_manifest` |
| `DESCRIPTION` exists but is not valid DCF (e.g. binary content) | `invalid_manifest` |

Edge case: a DESCRIPTION with both a valid `Config/intent/repos/CRAN` and a
malformed `Config/intent/repos//empty` should be `intent_manifest` (one valid
repo is enough) or `non_intent_manifest` (mixed validity is still invalid)?
The design in `022` says "produces a non-empty named repository vector" —
`get_repos()` filters to valid entries. The current implementation checks
`all(nzchar(repo_names))` and `all(nzchar(repos))`, so an empty-named repo
alongside a valid one would make the whole vector invalid. This is arguably
correct (fail closed), but the test should lock in this behaviour explicitly.

### Config Parse Error vs. Missing Config

Currently `get_repos()` (`R/desc.R:87-93`) wraps `read_intent_config()` in
`tryCatch` and silently returns `character()` on error. This means a
DESCRIPTION whose `Config/intent/` fields are so malformed that
`read_intent_config()` throws is classified identically to one with no
`Config/intent/` fields at all: both become `non_intent_manifest`.

Consider whether `classify_init_description()` should call
`read_intent_config()` directly (not through `get_repos()`) so it can
distinguish:
- `missing_config`: no `Config/intent/repos/*` fields at all
- `invalid_config`: fields exist but cannot be parsed

This distinction would enable better error messages. However, it is not
required for correctness — both cases are currently handled by the same
`non_intent_manifest` stop path. Defer this to implementation judgement.

### Switch Exhaustiveness

Add a default branch:

```r
stop_for_unsafe_init <- function(classification, renv_state) {
  switch(
    classification$type,
    invalid_manifest   = stop(...),
    non_intent_manifest = stop(...),
    missing_manifest   = { ... },
    intent_manifest    = NULL,
    stop(
      "Internal error: unknown init classification '",
      classification$type, "'.",
      call. = FALSE
    )
  )
  invisible(TRUE)
}
```

### Error Message Alignment (Two Options)

**Option A (minimal):** Narrow the `non_intent_manifest` error to only mention
what the classifier actually checks:

```r
"DESCRIPTION exists but is not an intent manifest. ",
"Add `Config/intent/repos/<NAME>` fields to declare project repositories. ",
"After the manifest is compliant, run `intent::init()` again."
```

**Option B (deeper):** Expand the classifier to also check for the presence of
at least one non-bootstrap dependency in `Imports` or `Suggests`. An empty
dependency list is technically a valid intent manifest but functionally
suspicious. This could be a separate `intent_manifest_empty` type or a warning.

Recommendation: start with Option A (minimal, correct, unblocks init for
legitimate edge cases). Option B can be a follow-up.

### `dir.create()` Location

Move `dir.create()` from `cmd_init()` line 17-19 into a helper or directly
inside the new-project branch:

```r
# Current (lines 12-19):
classification <- classify_init_description(project_dir)
renv_state <- init_renv_state(project_dir)
stop_for_unsafe_init(classification, renv_state)

if (!dir.exists(path)) {               # ← TOO EARLY
  dir.create(project_dir, recursive = TRUE)
}
```

Proposed: move `dir.create()` to just before DESCRIPTION creation, inside
the `missing_manifest` logic path (after `stop_for_unsafe_init` has
confirmed it's safe):

```r
stop_for_unsafe_init(classification, renv_state)

if (classification$type == "missing_manifest") {
  if (!dir.exists(path)) {
    dir.create(project_dir, recursive = TRUE)
  }
  # ... create new DESCRIPTION
}
```

For `intent_manifest` and `non_intent_manifest` / `invalid_manifest`, the
directory already exists by definition (it contains a DESCRIPTION). So
`dir.create()` is only needed for `missing_manifest` with no renv state.

### Eliminate Redundant File Check

Replace:

```r
if (!file.exists(desc_path)) {
  message("Creating DESCRIPTION file...")
  rproject <- desc::description$new("!new")
  rproject$set("Package", pkg_name)
} else {
  rproject <- desc::description$new(desc_path)
}
```

with a branch on the classification type directly:

```r
if (classification$type == "missing_manifest") {
  message("Creating DESCRIPTION file...")
  rproject <- desc::description$new("!new")
  rproject$set("Package", pkg_name)
} else {
  rproject <- desc::description$new(desc_path)
}
```

This is semantically identical (the classifier already checked
`file.exists(desc_path)`) but removes the TOCTOU window and makes the
intent explicit.

### User-Facing Classification API

Consider adding an exported function or a `dry_run`-like mode so users can
inspect classification before committing to init. Options:

```r
# Option 1: exported classifier
intent::classify(path = ".")

# Option 2: dry-run on init
intent::init(dry_run = TRUE)
```

Both require a `print()` method for the classification result. This is
lower-priority than the hardening changes above; defer to implementation
judgement. If added, define an S3 class `intent_init_classification` with
a `print()` method.

## Implementation Steps

1. Add 8+ direct unit tests for `classify_init_description()` covering all
   four types and edge cases (empty repo URL, NA name, mixed valid/invalid).
2. Add default fallthrough branch to `stop_for_unsafe_init()`.
3. Align `non_intent_manifest` error message with what the classifier checks
   (Option A: narrow the message to repos only).
4. Move `dir.create()` inside the `missing_manifest` branch.
5. Replace `file.exists(desc_path)` check with classification type dispatch.
6. (Optional) Add `intent::classify()` or `init(dry_run = TRUE)` for user
   inspection of classification results.
7. Verify all existing init tests still pass after refactoring.

## Test Plan

### Direct classifier tests (new)

- `intent_manifest`: valid DESCRIPTION with one named repo.
- `intent_manifest`: valid DESCRIPTION with multiple named repos.
- `non_intent_manifest`: DESCRIPTION without `Config/intent/` fields.
- `non_intent_manifest`: `Config/intent/repos/` with empty URL value.
- `non_intent_manifest`: `Config/intent/repos/` with empty name.
- `non_intent_manifest`: mixed valid and invalid repo fields.
- `missing_manifest`: no DESCRIPTION file.
- `invalid_manifest`: unparseable DESCRIPTION content.

### Safety gate tests (modified existing)

- `stop_for_unsafe_init()` with unknown type → internal error, not silent pass.
- `cmd_init()` with `missing_manifest` → `dir.create()` only called for
  new-project path, not for intent_manifest path.

## Acceptance Criteria

- `classify_init_description()` has direct unit tests for all four types plus
  edge cases.
- `stop_for_unsafe_init()` stops on unknown classification types.
- `non_intent_manifest` error message matches what the classifier checks.
- `dir.create()` only executes when init will definitely proceed.
- No redundant `file.exists(desc_path)` check in `cmd_init()`.
- All existing init tests pass without modification (or with minimal,
  intentional updates to match new error message wording).
- Code reviewers can understand the classification logic by reading the tests.

## Result / Follow-Up Notes

Fill this in after implementation.

- Result: Added 8 direct unit tests for `classify_init_description()` covering
  all four classification types plus edge cases (empty repo URL, empty repo
  name, mixed valid/invalid repos). Added default fallthrough branch to
  `stop_for_unsafe_init()` switch that stops on unknown classification types.
  Narrowed `non_intent_manifest` error message to mention only repos (not
  Imports/Suggests). Moved `dir.create()` inside the `missing_manifest` branch
  of `cmd_init()` and replaced the redundant `file.exists(desc_path)` check
  with `classification$type` dispatch. Added integration test verifying
  byte-identical preservation of user bootstrap constraints through init.
  Updated one existing test regex to match the narrowed error message.
- Follow-up work: Optionally expose `intent::classify()` or
  `init(dry_run = TRUE)` for user inspection of classification before
  committing to init. Consider distinguishing `invalid_config` from
  `missing_config` in the classifier for better error messages.
