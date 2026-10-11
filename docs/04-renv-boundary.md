# renv Boundary

`renv` is part of the current implementation. Under the accepted
[product boundary](06-product-boundary.md), intent owns user-facing dependency
contracts and workflows while environment management remains a separate backend
responsibility. The [capability assessment](09-backend-capability-matrix.md) records what has been evaluated and what remains unresolved. Keep suitable mechanisms and replace those that cannot satisfy the
required behavior; renv session behavior must not define intent's semantics.

## Target Relationship

`intent` owns the product model:

- project intent
- dependency declaration
- repository and source policy
- drift detection
- operation planning
- lockfile normalization
- project invariant verification
- user-facing commands

Backend mechanics currently delegated to `renv`, subject to capability evaluation:

- project-local library management
- lockfile writing and reading
- package restore
- package removal where appropriate
- activation files where appropriate

## Boundary Rules

1. Public commands should accept or discover a project path before they call the
   backend.
2. Core functions should not call `renv::project()`.
3. Direct calls to `renv` should be isolated in adapter functions.
4. Backend calls should pass required state explicitly, including project,
   library, lockfile, repositories, snapshot type, and prompt behavior.
5. Backend calls should not depend on ambient `.libPaths()`, `options(repos)`,
   current working directory, automatic settings discovery, or platform-specific
   defaults.
6. Any `renv` operation that writes a lockfile should be followed by
   intent-owned normalization before the official `renv.lock` is replaced.
7. Tests for parsing, planning, and command semantics should not need network
   access or a real package install.
8. Backend tests may use `renv`, but they should be marked or organized as
   integration tests.

## Current Coupling Risks

Current implementation patterns that should be reduced:

- `renv::project()` used as a global source of truth.
- `sync(project = ...)` accepting a project path while still requiring active
  `renv` session state.
- `add()` and `remove()` relying on loaded backend state before resolving the
  project.
- Repository loading tied to `renv::project()` rather than an explicit project
  path.
- `renv::snapshot()` being trusted to preserve repository metadata and snapshot
  mode without intent verifying the resulting lockfile.
- Tests whose behavior changes depending on packages already installed in the
  caller's library.

These patterns make command behavior harder to reason about and harder to expose
through a terminal CLI.

## Adapter Contract

The first adapter can be called `renv_backend`. Its contract should be narrow:

```r
renv_backend_init(project, repos)
renv_backend_install(project, packages, repos, library)
renv_backend_remove(project, packages)
renv_backend_snapshot(project, repos, library, lockfile, type)
renv_backend_restore(project, repos, library, lockfile)
renv_backend_read_state(project)
```

The rest of the package should not need to know how those functions work.

The adapter should be treated as an execution engine, not a source of truth.
When an adapter writes state that will become durable project state, the command
layer should pass the result back through intent core for normalization and
verification.

## Lockfile Write Rule

`renv.lock` should not be replaced directly by a backend call when intent has
project policy to enforce.

Preferred flow:

1. Ask `renv` to write a candidate lockfile.
2. Read the candidate.
3. Replace `$R$Repositories` with repositories declared in `DESCRIPTION`.
4. Validate source policy and repository names.
5. Apply bootstrap package rules.
6. Write the normalized lockfile to the official path.

This rule exists because `renv` behavior can vary with platform, explicit
arguments, project settings, and session state. intent should make those
differences irrelevant to the final project contract.

## Explicit Project Resolution

Project resolution should happen once near the top of each command.

Possible resolution order:

1. Explicit `project` argument.
2. Current working directory if it contains `DESCRIPTION`.
3. Parent directory search for `DESCRIPTION`.
4. Backend-specific active project only as a fallback.

If resolution fails, return a clear error:

```text
No intent project found. Run `intent init` or pass `project =`.
```
