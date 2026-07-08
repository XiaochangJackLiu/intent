# Intent Bootstrap Lifecycle

Status: `implemented`

## Problem

`intent` has two roles:

- A bootstrap tool that initializes or manages a project.
- A project tool dependency that can be loaded with `library(intent)` after
  `renv` activates the project library.

Those roles are easy to confuse. A user can install `intent` globally or from a
source such as GitHub, CRAN, R-universe, Posit Package Manager, or a self-hosted
repository, then run:

```r
intent::init("my_project")
```

After restarting R inside `my_project`, `renv` activates the project library. If
`intent` was not installed into that project library, `library(intent)` fails
even though the same user just used `intent` to create the project.

## Decision

Treat `DESCRIPTION` as the project intent file and `renv.lock` as the resolved
state file:

- `DESCRIPTION` is analogous to `pyproject.toml`.
- `renv.lock` is analogous to `uv.lock`.

`intent::init()` should continue to declare `intent`, `pak`, and `renv` in
`DESCRIPTION`. This records that the project expects those tools.

However, `intent` must not assume its own remote source. The package may be
hosted on CRAN, R-universe, GitHub, Posit Package Manager, a self-hosted package
manager, or a local development checkout. Hard-coding one source would break
users with private or mirrored infrastructure.

Therefore, `intent::init()` uses a local hydration policy by default:

```r
intent::init(install_self = "hydrate")
```

This attempts to copy the currently installed `intent` package from the active
library paths into the new project library through the `renv` backend. It does
not install `intent` from a remote repository. If hydration succeeds, `intent`
is available after restart and is recorded in `renv.lock`. If hydration fails,
initialization still succeeds and the user receives guidance.

Users can opt out:

```r
intent::init(install_self = "never")
```

In that mode, `intent` remains an external tool. This is useful for users who
prefer a global CLI-style workflow or who manage tool installation separately.

## User Journey

### 1. Install the bootstrap tool

The user installs `intent` into a normal user or site library from the source
appropriate for their organization.

Examples:

```r
install.packages("intent")
pak::pkg_install("XiaochangJackLiu/intent")
install.packages("intent", repos = "https://r.example.com/packages/latest")
```

At this stage, `intent` is outside any target project.

### 2. Initialize a project

The user calls:

```r
intent::init("my_project")
```

`init()` writes the project intent into `DESCRIPTION`, initializes `renv`, and
attempts to hydrate the already-installed `intent` package into the project
library.

### 3. Restart R

After restart, `renv` activates the project library.

If hydration succeeded:

```r
library(intent)
intent::add("dplyr")
```

If hydration did not succeed, the project is still initialized. The user can
install `intent` from their chosen source or use an external CLI workflow once
one is available.

### 4. Collaborate on another machine

Another machine may not already have `intent`. This is acceptable and mirrors
the `renv` and `uv` model: users who adopt the tool know they need the tool
available to operate the project. The project still records its intent in
`DESCRIPTION` and its resolved state in `renv.lock`.

## Non-Goals

- Do not hard-code GitHub, CRAN, or R-universe as the source for `intent`.
- Do not require self-hydration to succeed for project initialization to
  succeed.
- Do not implement a global CLI launcher in this refactor.
- Do not add a remote `self_source` installer until the source policy is designed
  separately.

## Implementation Plan

1. Add an `install_self` argument to `init()` and `cmd_init()`.
2. Support `install_self = "hydrate"` and `install_self = "never"`.
3. Add a backend hydration helper that calls `renv::hydrate()` with the current
   library paths as sources and no remote repositories.
4. Snapshot the project when hydration succeeds so `renv.lock` records the
   project tool dependency.
5. Add tests for default hydration, opt-out behavior, and non-fatal hydration
   failure.
6. Update user-facing documentation.

## Acceptance Criteria

- `intent::init()` defaults to local self-hydration.
- `intent::init(install_self = "never")` leaves `intent` external.
- Hydration failure does not fail `init()`.
- The decision is documented without assuming a specific package hosting source.

## Result / Follow-Up Notes

- Result: Added `install_self = "hydrate"` to `init()` and `cmd_init()`, added
  `backend_hydrate()`, and made self-hydration best-effort and source-neutral.
  Updated README and tests. Expanded `sandbox/e2e-test.R` to install `intent`
  into a temporary bootstrap library, initialize a real project, verify
  post-restart availability after `renv` activation, and exercise add, remove,
  sync, JSON output, and prune behavior.
- Additional result: The end-to-end test exposed backend boundary gaps. Snapshot
  operations now force through local hydrated tool records, restore excludes the
  `intent` tool package and targets the project library explicitly, remove
  targets the project library explicitly, and sync pruning preserves transitive
  dependencies by computing the lockfile dependency closure before pruning.
- Follow-up work: Design a separate global CLI launcher and, if needed, an
  explicit remote self-install policy that works with CRAN, R-universe, GitHub,
  self-hosted package managers, and local development sources.
