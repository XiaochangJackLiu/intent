# Isolate Explicit Repository Contracts from Ambient CI Configuration

Status: `in-progress`
Date: 2026-10-12

## Problem and evidence

Commit 76e33f0 passed local Windows tests, but remote run 38155167353 failed
restoration on both macOS and Windows. Its Linux-created lock recorded renv's
Repository as the runner's Linux-specific PPM URL despite a cloud CRAN manifest.
Run 38155167352 also failed Linux release/oldrel integration checks with multiple
installed-source mismatches; quality and Windows/macOS package checks passed.

setup-r injects RENV_CONFIG_REPOS_OVERRIDE. renv 1.3.1's native restore normalizer
removes record Repository when that configuration is nonempty, even if an explicit
repos argument is supplied. Its PPM normalization can also rewrite repository URLs.
renv's bootstrap reads the override environment variable directly. Consequently
passing repos alone does not isolate the accepted project repository contract.

## Goal and proposed changes

Preserve explicit project/lock source identities without relaxing validation or
changing runner setup for dependency installation. During backend restoration,
temporarily override renv.config.repos.override with character() and disable
renv.config.ppm.enabled. Keep transport Repository URLs, strict restoration and
the existing targeted source-repair path. Restore caller options on every exit.

During bare initialization, scope RENV_CONFIG_REPOS_OVERRIDE to the explicitly
selected repositories so renv bootstrap cannot record the runner's unrelated
mirror. Restore the previous environment value (including unset state) on exit.
Inspect real reproduction results for any additional provenance defect before
expanding the fix. No dependency explanation implementation belongs to this fix.

Public configuration reference:
https://pkgs.rstudio.com/renv/reference/config.html

## Validation

- Regression tests with conflicting override environment/options prove that
  native restore retains explicit URL identities and restores configuration on
  both success and failure.
- Initialization tests prove bootstrap receives selected repositories and that
  the caller's override, or absent variable, is restored.
- Reproduce initialization and lock restoration under CI-like override locally;
  run the relevant contract tests and full suite after implementation.
- Push the scoped fix and inspect remote package-check and cross-platform restore
  results. A local pass alone does not establish hosted cross-platform success.

## Result

Implemented bootstrap override scoping and native restore option isolation.
All 26 contract cases (121 assertions) passed. The full suite under the runner's
Linux-specific RENV_CONFIG_REPOS_OVERRIDE passed 175 cases and 541 assertions,
with no failures, errors, test warnings or skips. Real lower/exact/upper constraint
and unchanged-lock restoration experiments also passed with an invalid ambient
override URL, proving the explicit project target is used. Pre-commit checks passed.

Hosted run 38156519078 passed Linux project creation and both macOS/Windows
restorations. Run 38156519132 passed quality and Windows/macOS package checks;
all three Linux versions now have one remaining add/remove integration failure.
The candidate includes Linux mirror provenance from a restored seed library.

The seed path currently uses backend_restore without the source verification and
targeted repair applied to the final project library. A cache hit can therefore
contaminate the candidate before validation. Extend existing drift/verification
helpers with an explicit library target and verify/repair the seed before giving
it to the resolver. Preserve strict candidate validation and official lock
protection. Tests must cover the seed target, cache source repair and a failed
seed verification stopping resolution. Re-run local and hosted checks.

The dependency explanation proposal remains separate and no new user-facing
feature is included here.

Seed-verification follow-up: all 28 contract cases (128 assertions) passed.
The full CI-configuration rerun passed add/remove and the remaining tests except
sync initialization, where pak failed to install the R6 binary. A focused rerun
of that sync case passed both assertions without code changes. Pre-commit checks
passed. Hosted validation of this follow-up remains pending.
