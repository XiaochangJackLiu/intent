# Adopt Migration Plan

Status: `planned`

## Problem

`intent::init()` is now intentionally conservative. It refuses to infer project
intent from existing `renv.lock` or `renv/` state unless the project already has
an intent-compliant `DESCRIPTION`.

That protects existing projects from accidental lockfile rewrites, but it leaves
users with existing R or renv projects needing an explicit migration workflow.
They need a command that can inspect current state, explain what must change,
and only mutate files after review.

## Goal

Add an explicit adoption workflow for existing projects.

The workflow should:

1. inspect `DESCRIPTION`, `renv.lock`, `renv/`, and intent configuration;
2. produce a migration plan by default;
3. separate direct user intent from resolved lockfile state;
4. reuse bootstrap dependency planning from refactor 023;
5. apply changes only when explicitly requested.

The key product distinction is:

```r
intent::init()   # safe initialization for new or already-compliant projects
intent::adopt()  # explicit migration for existing projects
```

## Non-Goals

- Do not make `init()` adopt existing projects implicitly.
- Do not infer direct dependencies from `renv.lock` without user review.
- Do not scan source files for package usage in the first implementation.
- Do not implement a full dependency solver.
- Do not automatically delete or rewrite `renv.lock` in dry-run mode.
- Do not replace `renv` migration mechanics; use intent's manifest/state model
  to orchestrate them.

## Proposed API

Add a public function:

```r
adopt <- function(
  path = ".",
  repos = NULL,
  strategy = c("manifest", "lockfile-assisted"),
  dry_run = TRUE,
  install_self = "hydrate",
  confirm = interactive()
)
```

Default behavior should be non-mutating:

```r
intent::adopt()
# equivalent to dry_run = TRUE
```

Apply mode should require an explicit opt-in:

```r
intent::adopt(dry_run = FALSE)
```

The CLI can mirror this later:

```sh
intent adopt
intent adopt --apply
```

## Adoption Strategies

### `strategy = "manifest"`

This is the default and safest strategy.

It requires an existing parseable `DESCRIPTION`. It treats `DESCRIPTION` as the
source of direct dependency intent and does not infer new direct dependencies
from `renv.lock`.

The plan may add:

- missing `Config/intent/repos/*` fields;
- missing bootstrap dependencies (`intent`, `pak`, `renv`);
- `.Renviron` pak configuration;
- recommended renv explicit snapshot settings.

It may report:

- packages present in `renv.lock` but absent from `DESCRIPTION`;
- packages declared in `DESCRIPTION` but absent from `renv.lock`;
- repository mismatches between `DESCRIPTION` and `renv.lock`;
- bootstrap dependency conflicts from the 023 planner.

### `strategy = "lockfile-assisted"`

This strategy may read `renv.lock` to help users identify candidate direct
dependencies, but it still must not blindly write lockfile packages into
`DESCRIPTION`.

The plan may include a candidate section:

```text
Candidate dependencies from renv.lock:
  dplyr
  ggplot2
  readr

Likely transitive dependencies:
  rlang
  vctrs
  cli
```

The first implementation can keep this candidate report conservative:

- list lockfile packages missing from `DESCRIPTION`;
- mark them as "needs review";
- do not automatically classify them as `Imports` or `Suggests`;
- do not apply them unless a future explicit selection UI/API is designed.

## Plan Object

Add an internal adoption plan object:

```r
adoption_plan(project, strategy, repos)
```

Suggested structure:

```r
list(
  project = "/path/to/project",
  strategy = "manifest",
  actions = data.frame(
    action = character(),
    target = character(),
    detail = character()
  ),
  bootstrap = bootstrap_dependency_plan,
  issues = data.frame(
    area = character(),
    severity = character(),
    message = character()
  ),
  candidates = data.frame(
    package = character(),
    source = character(),
    reason = character()
  ),
  ok = TRUE
)
```

Actions should be concrete and reviewable, for example:

```text
add Config/intent/repos/CRAN = https://cran.r-project.org
add Suggests: intent (>= 0.1.0)
add Suggests: pak
add Suggests: renv
append .Renviron: RENV_CONFIG_PAK_ENABLED = TRUE
set renv snapshot.type = explicit
```

## Apply Model

Add an internal helper:

```r
apply_adoption_plan(plan)
```

It should:

- refuse to run when `plan$ok` is `FALSE`;
- write only the actions listed in the plan;
- preserve existing user-authored dependency constraints;
- use the bootstrap apply helper from 023;
- avoid rewriting `renv.lock` directly;
- call existing sync/verify helpers only after manifest changes are applied and
  policy checks pass.

For the first implementation, apply mode should not automatically add candidate
dependencies discovered from `renv.lock`.

## Safety Rules

- `dry_run = TRUE` must not mutate files, install packages, snapshot, or restore.
- `dry_run = FALSE` must only apply actions present in the plan.
- Existing `DESCRIPTION` dependency constraints win.
- Existing `renv.lock` is state, not intent.
- Any lockfile update should go through existing policy-aware snapshot helpers.
- If the plan has blocking issues, apply mode must stop before writing.

## User-Facing Output

Dry-run output should be compact and reviewable:

```text
Adoption plan for /path/to/project

Actions:
  + add Config/intent/repos/CRAN = https://cran.r-project.org
  + add Suggests: intent (>= 0.1.0)
  + add Suggests: pak
  + add Suggests: renv
  + append .Renviron: RENV_CONFIG_PAK_ENABLED = TRUE

Preserved:
  = Suggests: renv (== 1.1.4)

Issues:
  ! renv (< 1.0.0) conflicts with intent requirement renv (>= 1.1.0)

Candidates:
  ? dplyr is present in renv.lock but missing from DESCRIPTION
```

The output should make it clear that candidate dependencies are advisory unless
the user explicitly selects or writes them into `DESCRIPTION`.

## Interaction With Existing Commands

- `init()` remains conservative and should not call `adopt()`.
- `status()` and `verify()` remain read-only inspection tools.
- `sync()` remains the operation that reconciles manifest, lockfile, and
  library after adoption.
- `add()` and `remove()` remain the preferred post-adoption dependency editing
  commands.

## Implementation Steps

1. Add an adoption plan structure and empty dataframe helpers.
2. Implement `adoption_plan()` for `strategy = "manifest"`.
3. Reuse `bootstrap_dependency_plan()` inside adoption planning.
4. Add dry-run print/format support for adoption plans.
5. Add `adopt()` public function with `dry_run = TRUE` default.
6. Add `apply_adoption_plan()` for safe manifest/config writes.
7. Add `strategy = "lockfile-assisted"` candidate reporting.
8. Add CLI support after the R API is stable.
9. Update README, roxygen, and command design docs.

## Test Plan

Add focused tests for:

- `adopt(dry_run = TRUE)` does not modify files.
- `adoption_plan()` reports missing intent repos.
- `adoption_plan()` reuses bootstrap dependency planning.
- Existing bootstrap constraints are preserved.
- Bootstrap conflicts become adoption plan issues.
- Missing `DESCRIPTION` produces a blocking issue in manifest strategy.
- Existing `renv.lock` packages missing from `DESCRIPTION` are reported as
  candidates in lockfile-assisted strategy.
- Candidate dependencies are not applied automatically.
- `apply_adoption_plan()` refuses plans with blocking issues.
- `apply_adoption_plan()` writes only planned manifest/config changes.
- `init()` behavior is unchanged and does not call adoption helpers.

## Acceptance Criteria

- `intent::adopt()` exists and defaults to dry-run.
- Dry-run adoption never mutates files or backend state.
- Adoption planning reuses bootstrap dependency planning from 023.
- Existing `DESCRIPTION` remains the source of direct dependency intent.
- `renv.lock` is used only as state inspection or candidate assistance.
- Apply mode writes only reviewed plan actions.
- Blocking issues stop apply before mutation.
- User documentation clearly distinguishes `init()` from `adopt()`.

## Result / Follow-Up Notes

Fill this in after implementation.

- Result:
- Follow-up work:
