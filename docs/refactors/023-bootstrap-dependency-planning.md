# Bootstrap Dependency Planning

Status: `implemented`

## Problem

`intent::init()` now adds bootstrap tool dependencies (`intent`, `pak`, and
`renv`) with safer default version rules. That behavior is correct, but the
logic currently lives inside the init command path.

Future adoption and migration flows need the same bootstrap dependency rules,
but they should first show a plan before mutating `DESCRIPTION`. If bootstrap
dependency handling stays as direct mutation logic, `adopt()` will either
duplicate the init behavior or grow hidden special cases.

## Goal

Extract bootstrap dependency handling into a reusable plan/apply model.

The end state should allow command paths to:

1. inspect an existing `DESCRIPTION`;
2. compute what bootstrap dependency changes are needed;
3. report additions, preserved user constraints, and conflicts;
4. apply the accepted changes to `DESCRIPTION`.

`init()` may apply the plan immediately for safe init paths. A future `adopt()`
command should be able to return the same plan in dry-run mode before writing.

## Non-Goals

- Do not implement full `adopt()` in this refactor.
- Do not infer project dependencies from `renv.lock`.
- Do not scan source files for package usage.
- Do not install, restore, or snapshot packages as part of bootstrap dependency
  planning.
- Do not introduce public API arguments such as `bootstrap_versions =` unless a
  separate API design requires them.

## Current State

`cmd_init()` calls an internal helper that directly mutates the in-memory
`desc::description` object:

```r
set_missing_bootstrap_deps(rproject)
```

The helper:

- adds `intent`, `pak`, and `renv` to `Suggests` when missing;
- writes `intent (>= <running intent version>)`;
- copies `pak` / `renv` lower-bound constraints from the running `intent`
  package metadata when declared;
- preserves existing user constraints by skipping dependencies that already
  exist.

This is enough for init, but it cannot explain what it will do before doing it.
It also does not yet model conflicts between user constraints and intent's
minimum tool requirements.

## Proposed Design

### Bootstrap Dependencies

The bootstrap dependency set is:

```r
c("intent", "pak", "renv")
```

These packages are tool dependencies. They support managing the project; they
are not ordinary application runtime dependencies. They should continue to be
declared in `Suggests` by default.

### Default Version Policy

Default constraints are:

- `intent`: `>= <running intent version>`
- `pak`: copy `>= <minimum required by intent>` if declared in the running
  `intent` package metadata; otherwise no version constraint
- `renv`: copy `>= <minimum required by intent>` if declared in the running
  `intent` package metadata; otherwise no version constraint

The source of truth for `pak` and `renv` minimums is the running `intent`
package metadata, not the versions currently installed on the user's machine.

Only lower-bound constraints should be copied by default. Exact pins and upper
bounds belong either to user-authored `DESCRIPTION` constraints or to
`renv.lock`, not to default bootstrap policy.

### Manifest Wins

If `DESCRIPTION` already declares one of the bootstrap packages, that
declaration must be preserved by default.

Examples:

```dcf
Suggests:
    intent (>= 0.1.0),
    pak (>= 0.9.0),
    renv (== 1.1.4)
```

The plan should report these as preserved user constraints, not overwrite them.

### Plan Object

Add an internal plan object, for example:

```r
bootstrap_dependency_plan(rproject)
```

The returned object should contain:

- `add`: bootstrap dependencies missing from `DESCRIPTION` that should be added;
- `preserve`: bootstrap dependencies already declared by the user;
- `issues`: conflicts or invalid constraints requiring user attention;
- `ok`: whether the plan can be applied automatically.

An illustrative structure:

```r
list(
  add = data.frame(
    package = c("intent", "pak", "renv"),
    type = "Suggests",
    version = c(">= 0.1.0", "*", ">= 1.1.0")
  ),
  preserve = data.frame(
    package = "renv",
    type = "Suggests",
    version = "== 1.1.4"
  ),
  issues = data.frame(
    package = character(),
    severity = character(),
    message = character()
  ),
  ok = TRUE
)
```

The exact S3 class and print method can follow existing plan/status patterns in
the codebase if helpful.

### Applying a Plan

Add an internal apply helper:

```r
apply_bootstrap_dependencies(rproject, plan)
```

It should:

- add missing dependencies from `plan$add`;
- leave `plan$preserve` untouched;
- refuse to apply when `plan$ok` is `FALSE`;
- avoid writing files itself.

Command paths remain responsible for writing `DESCRIPTION`.

### Conflict Detection

The first implementation should detect obvious conflicts between user
constraints and intent's lower-bound requirements for `pak` and `renv`.

Example:

```dcf
Suggests:
    renv (< 1.0.0)
```

If the running `intent` metadata requires:

```dcf
Imports:
    renv (>= 1.1.0)
```

the plan should report an issue:

```text
renv constraint '< 1.0.0' conflicts with intent requirement '>= 1.1.0'
```

The planner does not need to implement a full SAT solver. A conservative first
pass can detect:

- user upper bounds lower than intent's required lower bound;
- user exact pins lower than intent's required lower bound.

If the constraint cannot be confidently evaluated, preserve it and report a
warning rather than rewriting it.

### Init Integration

`cmd_init()` should replace direct mutation:

```r
set_missing_bootstrap_deps(rproject)
```

with:

```r
plan <- bootstrap_dependency_plan(rproject)
apply_bootstrap_dependencies(rproject, plan)
```

For init, conflicts should stop before writing `DESCRIPTION`, because init is
not an interactive migration workflow.

### Future Adopt Integration

A future `intent::adopt()` command should use the same plan in dry-run output:

```text
Bootstrap dependencies:
  add intent (>= 0.1.0)
  add pak
  preserve renv (== 1.1.4)

Issues:
  renv (< 1.0.0) conflicts with intent requirement renv (>= 1.1.0)
```

This keeps adoption reviewable without giving `adopt()` a separate version
policy.

## Implementation Steps

1. Move existing bootstrap helper logic out of the init-specific mutation path
   into a planner.
2. Add a plan structure for additions, preserved constraints, and issues.
3. Add conflict detection for simple exact-pin and upper-bound conflicts against
   lower-bound requirements.
4. Add an apply helper that mutates only the in-memory `desc::description`
   object.
5. Update `cmd_init()` to plan, validate, and apply bootstrap dependencies.
6. Keep roxygen and README wording aligned with the plan/apply model if user
   facing behavior changes.

## Test Plan

Add focused unit tests for bootstrap planning:

- Missing `intent`, `pak`, and `renv` produce `add` plan entries.
- Existing bootstrap dependencies produce `preserve` entries and are not
  overwritten.
- `intent` default uses the running intent version.
- `pak` and `renv` lower bounds are copied from intent metadata when declared.
- Exact pins and upper bounds from intent metadata are not copied as defaults.
- User exact pins are preserved.
- User lower bounds satisfying intent requirements are preserved without issues.
- User exact pins below intent requirements produce issues.
- User upper bounds below intent requirements produce issues.
- `apply_bootstrap_dependencies()` refuses a plan with blocking issues.
- `cmd_init()` still writes the same bootstrap dependencies in safe init paths.

## Acceptance Criteria

- Bootstrap dependency behavior is represented as a plan before mutation.
- `init()` uses the planner and apply helper instead of direct dependency
  mutation.
- Existing user constraints for `intent`, `pak`, and `renv` remain manifest
  authority.
- Default `pak` and `renv` minimums come only from running `intent` metadata.
- Conflicts between user constraints and intent minimum tool requirements are
  surfaced before writing `DESCRIPTION`.
- The design is reusable by a future `adopt()` dry-run path.

## Result / Follow-Up Notes

- Result: Added `R/bootstrap.R` with reusable bootstrap dependency planning and
  apply helpers. `cmd_init()` now builds a bootstrap plan and applies it instead
  of directly mutating dependencies. The planner reports missing dependencies,
  preserved user constraints, and blocking conflicts for simple exact-pin or
  upper-bound cases that cannot satisfy intent's lower-bound requirements.
  Focused bootstrap tests cover defaults, preservation, lower-bound metadata,
  non-lower-bound metadata, conflict detection, and apply refusal.
- Follow-up work:
  - **Print/format/JSON methods** (`025`): `bootstrap_dependency_plan` has an S3
    class but no `print()` or `as.character()` method. These are prerequisites for
    `adopt()` dry-run output (`024`). Follow the existing patterns in
    `print.intent_plan`, `print.intent_status`, `as.character.intent_plan`.
  - **Warning severity**: Conflict detection only produces `severity: "error"`.
    The design specified warning-level issues for unparseable or ambiguous
    constraints (e.g. `renv (^1.0.0)` with npm-style syntax, or `> 1.0.0` where
    intent requires `>= 1.5.0` — not a conflict but worth noting). The `severity`
    column exists in the `issues` data frame but `"warning"` is never written.
    `ok` should check `severity == "error"` explicitly, not `any(issues)`.
  - **Input validation**: `bootstrap_dependency_plan()` does not validate its
    `versions` argument. A caller could inject an exact pin for `intent`
    (e.g. `c(intent = "== 1.0.0")`), contradicting the lower-bound policy.
    Add lightweight validation that `intent`'s version is a `>=` constraint.
  - **Temp DESCRIPTION robustness**: `bootstrap_metadata_deps()` writes a minimal
    temp DESCRIPTION that omits the required `Title` field. While `desc` currently
    tolerates this, it is fragile against future `desc` package changes. Add
    `Title: Internal Bootstrap Metadata Parser` to the temp file.
  - Reuse the bootstrap plan in a future `adopt()` dry-run output
    and decide whether to expose a user-facing plan print method (`024`, `025`).
