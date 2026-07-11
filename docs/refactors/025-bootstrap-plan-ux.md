# Bootstrap Plan User-Facing Output

Status: `implemented`

## Problem

`bootstrap_dependency_plan()` (`023`) produces a structured plan object with S3
class `bootstrap_dependency_plan`, but there is no `print()` or `as.character()`
method. The plan is invisible to users — `cmd_init()` calls the planner and
applier internally with no feedback about what was added, preserved, or flagged.

This blocks `adopt()` (`024`), whose dry-run output must render bootstrap
dependency changes in a human-readable format so users can review them before
applying.

Additionally, the plan's conflict detection only produces `severity: "error"`.
The design in `023` specified warning-level issues for constraints that cannot
be confidently evaluated. The `severity` column exists but `"warning"` is never
written. This means unparseable or ambiguous user constraints are silently
swallowed rather than surfaced for review.

## Goal

1. Add `print.bootstrap_dependency_plan()` following the existing
   `print.intent_plan` / `print.intent_status` patterns.
2. Add `as.character.bootstrap_dependency_plan()` for JSON serialisation,
   matching `as.character.intent_plan`.
3. Introduce `severity: "warning"` issues in `bootstrap_dependency_conflict()`
   and update the `ok` computation to only block on `severity == "error"`.

## Non-Goals

- Do not change the bootstrap dependency version policy.
- Do not add new conflict detection categories beyond what is described here.
- Do not expose a public `bootstrap_dependency_plan()` API — it remains internal.
- Do not implement `adopt()` dry-run output here; this only provides the
  building blocks `024` needs.

## Proposed Design

### print method

```r
print.bootstrap_dependency_plan <- function(x, ...) {
  cat("Bootstrap dependency plan:\n\n")

  if (nrow(x$add) > 0) {
    cat("Add:\n")
    for (i in seq_len(nrow(x$add))) {
      cat(sprintf(
        "  + %s (%s) [%s]\n",
        x$add$package[[i]], x$add$version[[i]], x$add$type[[i]]
      ))
    }
    cat("\n")
  }

  if (nrow(x$preserve) > 0) {
    cat("Preserve:\n")
    for (i in seq_len(nrow(x$preserve))) {
      cat(sprintf(
        "  = %s (%s) [%s]\n",
        x$preserve$package[[i]],
        x$preserve$version[[i]],
        x$preserve$type[[i]]
      ))
    }
    cat("\n")
  }

  if (nrow(x$issues) > 0) {
    cat("Issues:\n")
    for (i in seq_len(nrow(x$issues))) {
      cat(sprintf(
        "  %s [%s] %s: %s\n",
        if (x$issues$severity[[i]] == "error") "!" else "?",
        x$issues$severity[[i]],
        x$issues$package[[i]],
        x$issues$message[[i]]
      ))
    }
    cat("\n")
  }

  cat(sprintf("OK: %s\n", if (isTRUE(x$ok)) "TRUE" else "FALSE"))
  invisible(x)
}
```

The format mirrors `print.intent_plan` (`R/status.R:85-103`): project context,
categorised entries with leading markers (`+` / `=` / `!` / `?`), and a summary
line.

### JSON serialisation

```r
as.character.bootstrap_dependency_plan <- function(x, ...) {
  jsonlite::toJSON(unclass(x), auto_unbox = TRUE, pretty = FALSE)
}
```

This matches the pattern of `as.character.intent_plan` (`R/status.R:148-150`).
All data-frame columns are already atomic vectors, so `unclass()` produces a
JSON-serialisable list.

### Warning Severity

Add three warning scenarios to `bootstrap_dependency_conflict()`:

1. **Unparseable user constraint** — If `bootstrap_parse_version_constraint()`
   returns `NULL` for the user's version but the version string is non-empty and
   not `"*"`, emit a warning:
   ```
   renv constraint '^1.0.0' could not be parsed; preserving as-is
   ```

2. **User lower bound looser than intent's** — If user declares
   `renv (>= 0.5.0)` and intent requires `>= 1.5.0`, this is not a conflict
   (the resolver will pick >= 1.5.0). But the user may expect 0.9.0 to be
   acceptable, so surface an informational warning:
   ```
   renv constraint '>= 0.5.0' is looser than intent requirement '>= 1.5.0'
   ```

3. **User unbounded lower constraint** — If user writes `renv (> 1.0.0)` and
   intent requires `>= 1.5.0`, no conflict exists (1.5.0 satisfies both). But
   the user hasn't expressed an upper bound, which may be unintentional. Flag
   as a low-severity note only when intent has a known minimum.

The existing error scenarios (`==` below required, `<` / `<=` at-or-below
required) remain unchanged.

`bootstrap_dependency_plan()` already computes `ok` from `issues$severity`:

```r
ok = !any(issues$severity == "error")
```

This is already correct — only errors block. Warnings and informational notes
do not affect `ok`.

### Constraint Parse Failure Should Not Be Silent

Currently, `bootstrap_dependency_conflict()` returns `NULL` when
`bootstrap_parse_version_constraint()` returns `NULL` for either the user
or required version (`R/bootstrap.R:124-126`). This is correct for the required
version (if intent metadata is unparseable, that's an internal error, not a
user-facing conflict). But for the user version, returning `NULL` silently
ignores the unparseable constraint. The caller in
`bootstrap_dependency_plan()` loops over existing dependencies and calls
`bootstrap_dependency_conflict()` — if it returns `NULL`, the dependency is
preserved with no issue recorded.

Change the logic so that when the **user** version is unparseable (non-empty,
not `"*"`, not `NA`), a warning-level issue is returned instead of `NULL`.

## Implementation Steps

1. Add `print.bootstrap_dependency_plan()` in `R/bootstrap.R` or `R/status.R`.
2. Add `as.character.bootstrap_dependency_plan()` for JSON output.
3. Extend `bootstrap_dependency_conflict()` to return warning-level issues for
   unparseable user constraints.
4. Add warning-level issues for user lower bounds looser than intent
   requirements.
5. Export both S3 methods in `NAMESPACE`.
6. Add unit tests for print output format (snapshot or regex match).
7. Add unit tests for warning scenarios alongside existing error tests.

## Test Plan

- `print.bootstrap_dependency_plan()` with add entries produces expected markers.
- `print.bootstrap_dependency_plan()` with preserve entries shows preserved
  constraints.
- `print.bootstrap_dependency_plan()` with issues shows error and warning
  markers.
- `print.bootstrap_dependency_plan()` with empty plan shows "OK: TRUE".
- `as.character.bootstrap_dependency_plan()` returns valid JSON.
- Unparseable user constraint produces `severity: "warning"` issue.
- User `>=` looser than intent `>=` produces `severity: "warning"` issue.
- User `>` with intent `>=` produces `severity: "warning"` issue (informational).
- Existing error scenarios (`==`, `<`, `<=` below required) unchanged.
- `ok` is `FALSE` only when `severity == "error"` is present.
- `apply_bootstrap_dependencies()` still refuses when `!plan$ok`.

## Acceptance Criteria

- `bootstrap_dependency_plan` objects print in a human-readable format.
- `as.character()` produces valid JSON for machine consumers.
- Warning-level issues do not block `apply_bootstrap_dependencies()`.
- Error-level issues continue to block `apply_bootstrap_dependencies()`.
- Unparseable user constraints are surfaced instead of silently ignored.
- `024` can call `print()` on a bootstrap plan in its dry-run output.
- Existing bootstrap tests continue to pass.

## Result / Follow-Up Notes

Fill this in after implementation.

- Result: Added `print.bootstrap_dependency_plan()` and
  `as.character.bootstrap_dependency_plan()` S3 methods in `R/status.R`,
  following the existing `print.intent_plan` / `as.character.intent_plan`
  patterns. Extended `bootstrap_dependency_conflict()` in `R/bootstrap.R` with
  three new severity levels: `"warning"` for unparseable user constraints,
  `"warning"` for user `>=` looser than intent's `>=`, and `"info"` for user
  `>` with intent `>=`. Warnings and info issues do not affect `plan$ok`
  (only `severity == "error"` blocks). Added 9 focused tests for print output
  format, JSON round-trip, and warning/info scenarios.
- Follow-up work: Integrate formatted bootstrap plan output into `adopt()`
  dry-run display (`024`).
