# Cross-Platform Restore Safety

Status: `planned`

## Problem

`intent` delegates environment restoration to `renv::restore()`, which downloads
packages from the repositories declared in `Config/intent/repos/*`. This chain
works correctly on a single platform, but has no guard against three failure
modes that appear in cross-platform workflows:

1. **Platform-specific repository URLs.** A user writes a URL like
   `https://packagemanager.posit.co/cran/__linux__/manylinux_2_28/latest` into
   `Config/intent/repos/CRAN`. The lockfile records packages sourced from this
   URL. Another team member on macOS or Windows runs `intent::sync()` — PPM
   serves Linux binaries, and restore fails or installs incompatible packages.

2. **Repository name mismatch across platforms.** The lockfile records
   `Repository: RSPM` (Posit Package Manager's self-reported name), but
   `Config/intent/repos/` declares the same server under `CRAN`. `renv` cannot
   resolve `RSPM` unless `intent_supplement_repositories()` bridges the name
   via URL matching. This logic exists but has never been tested with lockfiles
   created on a different platform.

3. **No cross-platform restoration tests.** Every integration test that calls
   `intent::sync()` or `intent::init()` creates and restores the lockfile on
   the same machine in the same R session. There is no test that verifies a
   lockfile created on one OS can be restored on another — the exact scenario
   that occurs in CI/CD pipelines and mixed-OS teams.

`renv` and PPM handle the platform resolution when the repository URL is
platform-agnostic (e.g. `/cran/latest` — PPM auto-detects the client OS).
`intent`'s role is to ensure that the URLs it writes into `Config/intent/repos/`
and `renv.lock` are safe for cross-platform use, and to surface risks before
they cause silent failures.

## Goal

1. Detect platform-specific repository URLs and warn or block before they are
   persisted into `DESCRIPTION` or `renv.lock`.
2. Normalise default repository URLs to platform-agnostic forms during `init()`.
3. Add fixture-based and CI-driven tests that verify cross-platform lockfile
   restoration.
4. Document the cross-platform scenario classification so future work can
   reference a shared vocabulary.

## Non-Goals

- Do not add platform detection or binary negotiation to `intent::sync()` or
  `intent::restore()` — that is renv's responsibility.
- Do not change the on-disk format of `renv.lock`.
- Do not intercept or rewrite repository URLs in an existing lockfile.
- Do not add a full cross-platform CI matrix to the testing plan in this
  refactor — the CI pipeline change is scoped separately.

## Cross-Platform Scenario Classification

| Category | Description | Risk | Intent's Role |
|----------|-------------|------|---------------|
| **A** | Same-platform: lockfile created and restored on the same machine | None | Covered by existing integration tests |
| **B** | Platform-agnostic URL, cross-platform restore: lockfile uses `/cran/latest`, restored on any OS | Low | Golden path. PPM resolves server-side. **Untested.** |
| **C** | Platform-specific URL, cross-platform restore: lockfile uses `__linux__/...`, restored on macOS/Windows | **High** | Fails — wrong binaries. **Intent should prevent this URL from being written.** |
| **D** | Repository name mismatch: lockfile has `RSPM`, `Config/intent/repos/` has `CRAN`, same URL | Medium | `intent_supplement_repositories()` resolves via URL matching. Logic exists but **not tested cross-platform.** |
| **E** | Mixed-OS team: members on different OS share one lockfile | Medium | Requires platform-agnostic URLs. Intent can enforce this at `verify()` time. |
| **F** | CI/CD pipeline: Linux runner creates lockfile, developers restore locally | Low–Medium | Same as E — needs platform-agnostic URLs. CI repos must match declared repos. |

## Proposed Enforcement

### Enforcement 1: Repository URL Platform Detection

Add a validator that detects platform-specific segments in repository URLs.

**Trigger:** `init()` and `verify()`.

**Detection patterns:**

```
__linux__   __macos__   __windows__   __mac__   manylinux
```

**Behaviour at `init()` time:** When a user passes a platform-specific URL via
`repos =` or when `INTENT_DEFAULT_REPOS` contains one, emit a warning:

```text
Config/intent/repos/CRAN uses a platform-specific URL:
  https://packagemanager.posit.co/cran/__linux__/manylinux_2_28/latest
This repository will not be restorable on macOS or Windows.
Use a platform-agnostic URL: https://packagemanager.posit.co/cran/latest
```

Continue with init (warning, not error). The user may have a valid reason.

**Behaviour at `verify()` time:** Add a check in `intent_verify_project_issues()`
that scans all `Config/intent/repos/*` values. If any contain platform-specific
segments, report an issue:

- **Severity: `warning`** when `source-policy/mode` is `warn` or `off`.
- **Severity: `error`** when `source-policy/mode` is `error`.

This puts platform-agnostic URL enforcement under the existing source policy
framework — teams that want strict reproducibility can opt into `error` mode.

**Implementation:**

```r
repo_url_is_platform_specific <- function(url) {
  grepl("__(linux|macos|windows|mac)__|manylinux", url)
}

adopt_check_repo_urls <- function(repos) {
  # Returns adoption_issues_empty() or issues data.frame
}
```

**Location:** `R/status-core.R` or a new `R/cross-platform.R`.

### Enforcement 2: init() URL Normalisation

When `init()` writes the default repository (from `load_default_repos()` or
the `INTENT_DEFAULT_REPOS` env var), prefer a platform-agnostic URL.

**Current behaviour:** If `INTENT_DEFAULT_REPOS` is unset, init writes:
```
Config/intent/repos/CRAN: https://cran.r-project.org
```
CRAN is platform-agnostic (it serves source packages), so this is already safe.

If the user overrides with a platform-specific URL via `repos =` or the
`--repo` CLI flag, Enforcement 1 handles the warning.

**Proposed change:** Add a helper that maps known platform-specific PPM URLs
to their platform-agnostic equivalents:

```r
normalise_repo_url <- function(url) {
  # Already exists in R/status-core.R:789-791 — just strips trailing slash.
  # Extend to also normalise platform segments.
  # e.g. /cran/__linux__/manylinux_2_28/latest → /cran/latest
}
```

This is opt-in: the user must explicitly pass a platform-specific URL for it
to be stored. The normalisation only applies to the *default* repository
written during `init()`, not to user-provided repos.

### Enforcement 3: Lockfile Repository Resolvability

Already partially implemented in `intent_supplement_repositories()`
(`R/status-core.R:370-441`). This function detects when a lockfile package
record has a `Repository` name that is not declared in `Config/intent/repos/`,
and attempts to resolve it by matching the package's repository URL against
declared repository URLs.

**Gap:** The resolution only emits `message()` calls (lines 418-433). It never
produces verification issues that would appear in `intent::verify()` output or
block CI.

**Proposed change:** Add a verification issue when a lockfile package's
`Repository` name cannot be resolved against any declared repository, even
after URL matching. This catches the case where a lockfile from another
platform references a repository name that has no mapping on the current
platform.

**Severity:** `error` (the lockfile cannot be reliably restored).

## Testing Strategy

### Fixture-Based Lockfile Tests

Commit representative lockfiles under `tests/testthat/fixtures/` that were
created on different platforms or simulate platform-specific characteristics.

**Fixture files:**

| Fixture | Description | Tests |
|---------|-------------|-------|
| `lockfile-platform-agnostic.json` | `Repository: CRAN`, URL `/cran/latest` | `intent_restore()` resolves correctly. `verify()` passes. |
| `lockfile-rspm-name.json` | `Repository: RSPM`, URL `/cran/latest`, no `RSPM` in `Config/intent/repos/` | `intent_supplement_repositories()` resolves `RSPM` → declared repo by URL match. `verify()` reports no unresolvable repos. |
| `lockfile-platform-url.json` | `Config/intent/repos/CRAN` has `__linux__/...` URL | `verify()` reports platform-specific URL issue. |
| `lockfile-unresolvable-repo.json` | `Repository: UnknownRepo`, URL not matching any declared repo | `verify()` reports error: repository cannot be resolved. |

**Tests to add (in `test-cross-platform.R` or `test-status-dry-run.R`):**

- `repo_url_is_platform_specific()` returns TRUE for `__linux__`, `__macos__`, `manylinux` URLs
- `repo_url_is_platform_specific()` returns FALSE for `/cran/latest`, `https://cran.r-project.org`
- `verify()` with platform-specific repo URL reports issue
- `verify()` with platform-agnostic repo URL reports no issue
- `verify()` with unresolvable lockfile repository name reports error
- `intent_supplement_repositories()` resolves `RSPM` → `CRAN` when URLs match
- Source policy `mode: error` elevates platform-specific URL warning to error

### Cross-Platform CI Pipeline

Add a CI job (or extend the existing workflow) that tests cross-platform
lockfile restoration:

```
Job 1 (ubuntu-latest):
  1. intent::init() with platform-agnostic repos
  2. intent::add("dplyr")
  3. Upload renv.lock as CI artifact

Job 2 (windows-latest, macos-latest):
  1. Download renv.lock artifact
  2. intent::sync()
  3. Verify dplyr is installed in the project library
  4. intent::verify() reports no issues
```

This is scoped as a separate CI workflow change and is not part of the core
implementation in this refactor. The fixture-based tests provide fast,
deterministic coverage in the meantime.

### Conditional Platform Tests

Replace the hardcoded Linux-specific URL in `test-init.R:385` with a
platform-agnostic URL (`/cran/latest`). Add a separate test that verifies
intent warns when given a platform-specific URL:

```r
test_that("init warns on platform-specific repo URL", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  expect_warning(
    cmd_init(
      path = tmp_dir,
      repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/manylinux_2_28/latest"),
      install_self = "never"
    ),
    "platform-specific"
  )
})
```

## Implementation Steps

1. Add `repo_url_is_platform_specific()` and `intent_check_platform_repos()`
   to `R/status-core.R` or a new file.
2. Integrate platform URL checking into `intent_verify_project_issues()` so
   `verify()` reports platform-specific URLs.
3. Add `adopt_check_repo_urls()` to `adopt_build_issues()` so `adopt()`
   reports platform-specific URLs in dry-run output.
4. Optionally warn during `cmd_init()` when user-provided repos contain
   platform-specific URLs.
5. Add fixture lockfiles to `tests/testthat/fixtures/`.
6. Add tests for platform URL detection, verification issues, and
   supplement resolution.
7. Fix the hardcoded Linux-specific URL in `test-init.R:385`.
8. Update `016-testing-plan.md` with cross-platform test entries.
9. (Separate) Add cross-platform CI artifact pipeline to GitHub Actions.

## Acceptance Criteria

- `intent::verify()` reports a warning or error when `Config/intent/repos/*`
  contains a platform-specific URL.
- `intent::init()` warns when a platform-specific URL is passed via `repos =`.
- `intent_supplement_repositories()` behaviour is tested with lockfile fixtures
  representing different repository naming conventions.
- `repo_url_is_platform_specific()` correctly classifies known platform-specific
  and platform-agnostic URL patterns.
- The hardcoded Linux-specific URL is removed from `test-init.R`.
- All existing tests pass without modification.

## Result / Follow-Up Notes

Fill this in after implementation.

- Result:
- Follow-up work:
