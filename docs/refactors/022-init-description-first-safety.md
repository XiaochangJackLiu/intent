# Init DESCRIPTION-First Safety

Status: `implemented`

## Problem

`intent::init()` can currently mutate an existing project before it knows whether
the existing `DESCRIPTION` is a valid intent manifest. This makes init
potentially destructive for projects that already have `renv.lock`, `renv/`, or
both.

The unsafe behavior comes from treating init as a combined bootstrap and sync
operation:

- If `DESCRIPTION` is missing, init creates one and may then overwrite
  `renv.lock`.
- If `DESCRIPTION` exists but does not declare intent configuration, init adds
  intent dependencies and repository fields, then snapshots and restores.
- If `renv/` exists, init skips `renv::init()` but still snapshots and restores,
  which can rewrite `renv.lock` according to the modified `DESCRIPTION`.

This violates the product model: `DESCRIPTION` is intent, and `renv.lock` is
state. Init should classify the manifest first and only write state when the
manifest is known to be safe for intent semantics.

## Goal

Make `intent::init()` description-first and non-destructive by default.

Before writing `DESCRIPTION`, `renv.lock`, `.Rprofile`, `.Renviron`, or the
project library, init must classify the project into one of these cases:

1. `DESCRIPTION` exists and is intent-compliant.
2. `DESCRIPTION` exists but is not intent-compliant.
3. `DESCRIPTION` does not exist.

The classification must happen before any backend call, snapshot, restore, or
file write.

## Non-Goals

- Do not implement automatic migration from arbitrary renv projects in this
  refactor.
- Do not infer dependencies from an existing `renv.lock`.
- Do not scan source files for `library()` or `require()` calls.
- Do not change `add()`, `remove()`, `sync()`, `status()`, or `verify()` unless
  a helper extracted for init is shared read-only logic.

## Current State

`cmd_init()` creates or mutates `DESCRIPTION` first, then branches on whether
`renv/` exists:

- Without `renv/`, it calls `backend_init()`, which calls `renv::init()` and
  writes `renv.lock`.
- With `renv/`, it calls `intent_sync_project()`, which snapshots to a candidate
  lockfile, overwrites the official `renv.lock`, and restores the library.

The presence of `renv.lock` is not checked before mutation. An existing lockfile
can therefore be overwritten even when the project has not explicitly opted into
intent's manifest format.

## Proposed Design

### Description Classification

Add an internal read-only classifier:

```r
classify_init_description(project)
```

It returns one of:

- `intent_manifest`: `DESCRIPTION` exists, parses successfully, and contains
  required intent configuration.
- `non_intent_manifest`: `DESCRIPTION` exists and parses, but is not yet an
  intent manifest.
- `missing_manifest`: `DESCRIPTION` does not exist.
- `invalid_manifest`: `DESCRIPTION` exists but cannot be parsed as a valid R
  `DESCRIPTION` file.

For the first implementation, "intent-compliant" means:

- the file is parseable as `DESCRIPTION`;
- `Config/intent/repos/*` exists and produces a non-empty named repository
  vector;
- each repository entry has a non-empty name and URL.

The classifier must not create, modify, or delete files.

### Package Version Declarations

`DESCRIPTION` may declare package version constraints, but init should not
require exact versions for every dependency.

The intended split is:

- `DESCRIPTION` declares direct dependency intent and compatibility constraints.
- `renv.lock` records the exact resolved package versions.
- `Config/intent/Imports/*` and `Config/intent/Suggests/*` are reserved for
  explicit source or version overrides when the normal dependency declaration is
  not enough.

This means these are all valid direct dependency declarations:

```dcf
Imports:
    dplyr,
    glue (>= 1.6.0)
Suggests:
    testthat (>= 3.0.0)
```

An exact version may be declared when the user really intends a strict
compatibility boundary:

```dcf
Imports:
    dplyr (== 1.1.4)
```

However, exact versions should not be required as part of intent compliance. If
every dependency had to be pinned in `DESCRIPTION`, `DESCRIPTION` would become a
second lockfile and could drift from `renv.lock`.

For this refactor, init only needs to preserve existing dependency version
constraints and avoid rewriting state for non-compliant manifests. Enforcing or
installing according to dependency version constraints is a follow-up sync/add
behavior concern, not an init safety requirement.

### Bootstrap Package Version Policy

`intent` is different from ordinary project dependencies because it is the tool
that will manage the project after init. For the self dependency that init adds
to `DESCRIPTION`, use an R-style lower-bound constraint:

```dcf
Suggests:
    intent (>= 0.0.1)
```

The version should be the version of the `intent` package that is executing
`init()`.

R package metadata does not have a standard Python-style compatible release
operator such as `~= 1.1.4` or `~1.1.4` in `DESCRIPTION`. A default exact pin
would also be too strict: it would make routine tool upgrades harder and would
partly duplicate `renv.lock`.

Therefore, the default policy is:

- `DESCRIPTION` records `intent (>= <current intent version>)` so future runs
  know the minimum tool capability the project was initialized with.
- `renv.lock` records the exact resolved `intent` version when `intent` is
  hydrated into the project library.
- Users who need stricter tool reproducibility can rely on `renv.lock` or add an
  explicit override later.

For `pak` and `renv`, init should derive minimum version constraints from the
installed `intent` package metadata when available.

`intent` already declares its own runtime requirements in its package
`DESCRIPTION`. Init can read those declarations and copy the minimum required
versions into the target project's `DESCRIPTION`:

```dcf
Suggests:
    intent (>= <current intent version>),
    pak (>= <minimum required by intent>),
    renv (>= <minimum required by intent>)
```

The source of truth should be the installed `intent` package metadata, not the
currently installed `pak` or `renv` versions. Runtime installed versions can be
newer than the true minimum and would make new projects unnecessarily
restrictive.

If `intent` does not declare a minimum for `pak` or `renv`, init should preserve
the current behavior and add the package without a version constraint. This
keeps the policy honest: `intent` should only write minimums that it actually
knows and tests against.

Implementation can use `utils::packageDescription("intent")` or the local
package metadata available to the running package, parse dependency fields, and
extract lower-bound constraints for `pak` and `renv`. Only lower-bound
constraints should be copied by default. Exact pins and upper bounds should not
be introduced automatically unless intent itself later adopts an explicit
compatibility policy for those tools.

### User Overrides for Bootstrap Tool Versions

Users should be able to customize the `intent`, `pak`, and `renv` version
constraints, but those customizations should be explicit manifest intent.

For existing `DESCRIPTION` files, init must preserve user-specified dependency
constraints for `intent`, `pak`, and `renv`. If a user has already written:

```dcf
Suggests:
    intent (>= 0.1.0),
    pak (>= 0.9.0),
    renv (== 1.1.4)
```

init should not silently loosen, tighten, or replace those constraints.

For new projects, optional arguments may be added later if the CLI/API needs a
convenient creation-time override, for example:

```r
intent::init(
  bootstrap_versions = c(
    pak = ">= 0.9.0",
    renv = "== 1.1.4"
  )
)
```

However, this refactor does not require adding that API. The first rule is that
the manifest wins:

1. If `DESCRIPTION` already declares a bootstrap tool version constraint,
   preserve it.
2. Otherwise, write intent's default bootstrap constraints.
3. If a future init argument is added, it should only apply when creating or
   explicitly amending a manifest, and the resulting constraint should be written
   back to `DESCRIPTION`.

This keeps version policy reviewable in normal diffs and avoids hidden local
configuration deciding which package manager versions a project requires.

### Init Decision Matrix

`intent::init()` should use the classifier before any mutation.

| Case | Existing renv state | Default behavior |
| --- | --- | --- |
| `intent_manifest` | none | Initialize backend, hydrate if requested, write `.Renviron`. |
| `intent_manifest` | `renv/` and/or `renv.lock` | Continue as an intent project and sync through the normal intent path. |
| `non_intent_manifest` | any | Stop before writing. Explain that the project must be migrated by adding required `Config/intent/` fields and verifying `DESCRIPTION` dependencies. |
| `invalid_manifest` | any | Stop before writing. Report that `DESCRIPTION` cannot be parsed. |
| `missing_manifest` | no `renv/` and no `renv.lock` | Treat as a new project and create `DESCRIPTION`, backend state, and config. |
| `missing_manifest` | `renv/` and/or `renv.lock` | Stop before writing. Existing state without a manifest is unsafe to adopt automatically. |

This keeps the destructive operations behind an explicit manifest contract. If a
project already has `renv` state but no intent-compliant `DESCRIPTION`, init
should not rewrite the lockfile or restore the library.

### Migration Guidance

For `non_intent_manifest`, the error should guide users to:

1. ensure `Imports` and `Suggests` list all direct dependencies they want intent
   to manage;
2. add `Config/intent/repos/<NAME>` fields;
3. run `intent::status()` or `intent::verify()` after initialization once the
   manifest is compliant.

For `missing_manifest` with existing renv state, the error should explain that
intent cannot safely infer project intent from `renv.lock` alone. Users should
create a `DESCRIPTION` first or use a future migration helper.

### Future Adopt Mode

A future explicit adoption path may be added, but it is intentionally outside
this refactor. Possible shapes:

```r
intent::init(adopt = TRUE)
intent::adopt()
```

That path would be allowed to create or amend intent configuration after an
explicit user request. It should still avoid inferring direct dependencies from
`renv.lock` without user review.

## Implementation Steps

1. Add read-only helpers for init classification and existing renv state
   detection.
2. Move classification to the top of `cmd_init()`, before any DESCRIPTION
   creation or mutation.
3. Preserve the current new-project path only for `missing_manifest` with no
   existing renv state.
4. Preserve the current sync path only for `intent_manifest`.
5. Add clear error messages for `non_intent_manifest`, `invalid_manifest`, and
   `missing_manifest` with existing renv state.
6. Update README and roxygen documentation after implementation to describe the
   safe init behavior.

## Test Plan

Add unit tests with backend calls stubbed:

- Existing intent-compliant `DESCRIPTION` without renv state may call
  `backend_init()`.
- Existing intent-compliant `DESCRIPTION` with `renv/` may call
  `intent_sync_project()`.
- Existing non-intent `DESCRIPTION` does not call `backend_init()`,
  `intent_sync_project()`, `maybe_hydrate_intent()`, or write the file.
- Invalid `DESCRIPTION` stops before backend calls.
- Missing `DESCRIPTION` in an empty directory keeps the current new-project
  behavior.
- Missing `DESCRIPTION` with existing `renv.lock` stops and leaves the lockfile
  untouched.
- Missing `DESCRIPTION` with existing `renv/` stops and leaves the directory
  untouched.

Add at least one test that records the original `DESCRIPTION` and `renv.lock`
contents and verifies they are unchanged after a refused init.

## Acceptance Criteria

- `intent::init()` performs a read-only project classification before any
  mutation.
- Refused init paths do not modify `DESCRIPTION`, `renv.lock`, `.Rprofile`,
  `.Renviron`, or the project library.
- Existing intent-compliant projects continue to initialize or sync through the
  existing backend path.
- Empty directories continue to work as new projects.
- Existing renv state without an intent-compliant `DESCRIPTION` is never
  overwritten by default.
- Package version constraints in `DESCRIPTION` are preserved, but exact package
  versions are not required for init compliance.
- Documentation explains the three description-first cases and the migration
  requirement for existing renv projects.

## Result / Follow-Up Notes

- Result: Implemented read-only init classification before mutation. Init now
  refuses non-intent or invalid `DESCRIPTION` files before backend calls, and it
  refuses missing `DESCRIPTION` when `renv.lock` or `renv/` already exists.
  Existing intent-compliant manifests continue through the backend init or sync
  paths. Existing intent-compliant projects with either `renv/` or `renv.lock`
  use the sync path instead of reinitializing the backend. Bootstrap
  dependencies now preserve user constraints, add `intent (>= <running version>)`
  by default, and copy known `pak` / `renv` lower bounds from the running
  `intent` package metadata when declared.
- Follow-up work: Design an explicit adoption or migration command for existing
  renv projects that do not yet have an intent-compliant `DESCRIPTION`.
