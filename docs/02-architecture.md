# Architecture

`intent` should be structured as a small product core with separate interfaces
and backend adapters.

The accepted [product boundary](06-product-boundary.md) makes intent responsible
for user-facing dependency contracts and workflows. Environment management is
a separate backend responsibility. The [capability assessment](09-backend-capability-matrix.md) records retained mechanisms, adaptations and remaining gaps.

## Target Layers

```text
CLI / R API
    |
Command Layer
    |
Intent Core
    |
Backend Adapters
```

The architectural contract is:

```text
DESCRIPTION declares.
intent enforces.
Backends execute.
The lockfile records resolved state (currently renv.lock).
```

`DESCRIPTION` and `Config/intent/` define the project contract. `renv.lock`
records the resolved state derived from that contract. Backend tools such as
`renv` and `pak` execute operations, but their defaults and session-dependent
behavior must not define intent's product semantics.

## Interfaces

Interfaces translate user input into command calls.

Examples:

- CLI: `intent add dplyr`
- R API: `intent::add("dplyr")`

Interface code should be thin. It should parse arguments, call the command
layer, print useful output, and return structured results where appropriate.

## Command Layer

The command layer owns product workflows. It answers what should happen for
each user command.

Examples:

- `cmd_init(project, repos, backend)`
- `cmd_add(project, packages, dev, backend)`
- `cmd_remove(project, packages, backend)`
- `cmd_sync(project, backend)`
- `cmd_status(project, backend)`

Commands should not directly manipulate `renv` internals. They should call core
functions and backend adapters.

Mutating commands should follow a consistent lifecycle:

1. Resolve the project.
2. Read the intent project model.
3. Validate the model before doing work.
4. Execute backend operations with explicit arguments.
5. Normalize backend outputs.
6. Verify the final project state.

## Intent Core

The core owns product concepts and should be easy to test without installing
packages.

Core responsibilities:

- Locate a project.
- Read and write manifest intent.
- Parse `Config/intent/` fields.
- Read lockfile state through an abstract state reader.
- Compare manifest dependencies to locked dependencies.
- Build operation plans.
- Normalize lockfile state against the project contract.
- Verify project invariants before and after mutating commands.

Potential core objects:

- `IntentProject`
- `IntentManifest`
- `IntentState`
- `IntentPolicy`
- `DependencySpec`
- `OperationPlan`

These do not need to be formal classes immediately. The important rule is that
core functions should operate on explicit data rather than hidden session state.

## Backend Adapters

Backends execute operations.

The first backend can use `renv` and `pak`, but it should be accessed through a
small adapter surface:

- `backend_init(project, repos)`
- `backend_install(project, packages, repos)`
- `backend_remove(project, packages)`
- `backend_snapshot(project, repos, lockfile, type)`
- `backend_restore(project, repos)`
- `backend_read_state(project)`

This keeps `renv` from spreading through the codebase. Adapter calls should
receive all state needed to behave deterministically, rather than relying on the
current working directory, `.libPaths()`, `options(repos)`, project settings
being rediscovered, or platform-specific backend defaults.

## Lockfile Normalization

Any backend operation that writes or rewrites `renv.lock` must write to a
candidate lockfile or equivalent temporary state first. Before replacing the
official project lockfile, intent must normalize and validate the candidate:

- `$R$Repositories` must match `Config/intent/repos/*` exactly.
- Snapshot behavior must be explicit.
- Lockfile package provenance must satisfy the source policy.
- Repository package records must use declared repository names.
- Bootstrap packages must follow explicit intent rules.

The official `renv.lock` should be replaced only after these checks pass, or
after violations are handled according to the configured policy mode.

## Current Architecture Smell

The current package mixes interface, workflow, core, and backend behavior in the
same functions. For example, public functions currently read `renv::project()`
directly and call `renv`/`pak` operations inline.

That creates these risks:

- Circular workflow assumptions between `init()`, `sync()`, and `renv::load()`.
- Commands that only work after a backend has already activated.
- Tests that require network or package installation for logic that should be
  unit-testable.
- No clean path to a CLI because there is no shared command layer.
- Backend output becoming official project state before intent can normalize it.

## Refactoring Direction

Refactor toward this dependency direction:

```text
R API / CLI -> commands -> core -> adapters
```

Avoid this direction:

```text
core -> R API
core -> CLI
core -> renv session globals
commands -> public functions
```

No lower layer should call a higher layer.
