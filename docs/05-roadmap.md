# Roadmap

This roadmap moves the project from the current implementation toward a clear
product and architecture. It intentionally starts with documentation and design
before deeper code changes.

## Current Next Steps (2026-10-11)

The accepted [product boundary](06-product-boundary.md) and proposed
[next-step plan](07-next-steps.md) define the current direction: preview safety,
user verb contracts, renv/pak capability evaluation, scoped implementation, then
feature selection. Backend replacement decisions require capability evidence.

The phases below record the original development roadmap; they are not a fresh
implementation queue or proof that every acceptance criterion has been met.
See the [consistency review](review-2026-10-11.md) for remaining discrepancies.

## Phase 0: Stabilize Direction

- Add development docs under `docs/`.
- Define the problem statement.
- Define the product principles.
- Define the `renv` boundary.
- Decide that the CLI and R API share one command layer.

Exit criteria:

- Contributors can explain what `intent` is and what it is not.
- New code can be reviewed against documented principles.

## Phase 1: Make Project Resolution Explicit

- Add a project resolution helper.
- Stop using `renv::project()` in core logic.
- Pass `project` paths through internal functions.
- Make `sync(project = ...)` work without requiring active `renv` state unless
  the backend operation itself requires it.

Exit criteria:

- Core parsing and planning tests run without a loaded `renv` project.
- Public commands have predictable project discovery.

## Phase 2: Separate Core from Backend

- Move manifest parsing and writing into core functions.
- Move lockfile/library operations into a backend adapter.
- Introduce operation plans for `add`, `remove`, `sync`, and `status`.
- Split unit tests from integration tests.

Exit criteria:

- Most tests do not install packages.
- Backend-specific behavior is isolated.

## Phase 3: Add Status and Dry Run

- Implement `intent::status()`.
- Add `dry_run = TRUE` support to mutating commands.
- Report drift between manifest, lockfile, and local library.

Exit criteria:

- Users can inspect what `intent` would change before changing it.

## Phase 4: Add CLI

- Add an installed CLI entry point.
- Implement `intent init`, `intent add`, `intent remove`, `intent sync`, and
  `intent status`.
- Ensure CLI commands call the same command layer as the R API.
- Add JSON output for `status`.

Exit criteria:

- A user can manage a project without opening an interactive R session.

## Phase 5: Refine Dependency Overrides

- Decide whether dependency overrides belong in `Config/intent/`.
- Define supported source formats.
- Define how override repositories interact with project repositories.
- Add validation and clear error messages.

Exit criteria:

- Overrides are documented, tested, and independent of backend internals.

## Immediate Next Decisions

The next implementation pass should answer:

- Should `init()` have a default repository, or should it require explicit
  repository configuration?
  → **Historical decision (July 2026):** refactor 009 selected Posit Package
  Manager. The 2026-10-11 review found that implementation now defaults to CRAN
  while other documentation still specifies PPM. Reconcile this decision in
  stage B of the current plan; do not treat the historical entry as resolution
  of that conflict.
- What is the exact project discovery algorithm?
  → **Resolved:** Implemented in `resolve_project()` in `R/utils.R`.
- What data structure represents drift?
  → **Resolved:** `intent_status` S3 object. See refactor 004.
- Which tests are unit tests and which are integration tests?
  → **Resolved:** Tests that install packages (`init`, `add/remove`, `sync`)
  are integration tests. Tests using stubs and fixtures (`desc`, `cli`,
  `status-dry-run`, `project-resolution`, `overrides`, `utils-repos`) are
  unit tests.
