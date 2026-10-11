# Dependency Contract Enforcement and Staged Reconciliation

Status: `implemented`
Date: 2026-10-11

## Problem

Audit findings 2–7, 9 and 10 remain after CLI containment. Sync ignores normal
constraints/source changes; some restoration paths bypass policy; initialization
and adoption can derive locks from incomplete libraries. Verification and
repository matching disagree, and backend calls escape adapters.

## Goal

Implement the accepted sync direction with an intent-owned plan and validation
layer. Keep renv for environment mechanics and pak for constrained resolution
where evidence supports them. All existing and newly designed unit scenarios
must pass before pushing the work.

## Decisions for this implementation

These are documented implementation defaults under the user's instruction to
proceed with the plan; the central sync resolution policy was explicitly chosen
earlier. They do not introduce a new public update verb or lockfile format.

- A valid lock is restored, never regenerated from library drift. Missing locks
  resolve; malformed locks fail before mutation.
- Resolve changed intent in a temporary library seeded from compatible locked
  records, using a synthetic dependency DESCRIPTION that carries constraints
  and source references. Prefer installed compatible seed versions.
- Validate a staged candidate before restoring the real library, then commit
  the lock only after restoration succeeds. Report partial library changes if
  a backend operation fails; do not promise a full cross-file transaction.
- Default prune removes true orphans. no-prune retains old extras and treats
  closure extras as warnings, while still enforcing their source policy.
- Source overrides must satisfy normal version constraints. Unknown/mismatched
  provenance must be reported rather than accepted as a verified identity.
- Init prepares backend infrastructure and reconciles declared dependencies.
  Adopt preserves user tool constraints by default, lists all backend effects,
  and uses the same reconciliation workflow after reviewed manifest changes.
- Record the intent tool's external/managed lifecycle explicitly when init/adopt
  chooses install_self. A deliberately external intent is not a missing managed
  dependency; no remote self source is assumed.
- Current CRAN defaults are documented consistently. URL-backed aliases are
  allowed; unrelated repository-table entries are not silently retained.
- Verify fails only on errors, compares full R/package versions and available
  source identities, and reports platform risks even with policy enforcement off.

## Backend evaluation and implementation steps

1. Record installed renv/pak versions, public API evidence and focused local
   experiments in the capability matrix. Verify constrained deps:: resolution
   before relying on it; adapt or replace if it fails the contract.
2. Add core dependency constraints, lock identity comparisons and unified repo
   matching. Cover missing metadata and conflicting constraints explicitly.
3. Add explicit adapter parameters for library, candidate lock, snapshot roots,
   clean/transactional restore and settings; keep renv calls in backend.R.
4. Build sync plans, stage compatible records, resolve required changes, validate
   the candidate, restore target and commit validated state. Preserve no-op locks.
5. Route add/remove/init/adopt through shared reconciliation as applicable.
   Update migration plans to describe configuration, hydration and state effects.
6. Extend status/verify and serialization with version/source drift, preserving
   existing fields. Reconcile docs, generated Rd, NEWS and CI target/restore scope.
7. Run focused unit tests, the full existing test suite, local backend experiments,
   formatting/documentation checks and Git diff review. Commit intended files
   only and push the current dev branch without force.

## Test plan and acceptance criteria

Designed unit scenarios: unchanged valid lock restored without snapshot;
empty/wrong-version library does not rewrite valid lock; absent lock resolves;
normal lower/exact/upper constraints trigger necessary resolution; compatible
constraint edits preserve locks; same-version source changes resolve; conflicting
override fails; forbidden existing source fails before mutation; invalid candidate
and failed restore preserve official lock; transitive dependencies survive remove;
no-prune retains extras when adding; external intent is exempt from managed-state
checks; adoption preserves user constraints and previews every side effect;
info/warnings do not fail verify; R patch versions compare correctly; old URL
records and table-backed aliases get consistent provenance verdicts.

Real backend evidence must include explicit projects/libraries without activation,
constrained resolver behavior, candidate snapshot, restore into an empty target,
and unchanged-lock restoration. Cross-platform CI must actually restore the
uploaded project's lock and must target the project explicitly.

## Result / follow-up

Implemented the shared planning, dependency contract validation, staged
reconciliation, backend adapters and status/verify semantics. Initialization,
adoption, add/remove and sync now use the same contract boundary. Valid compatible
locks are restored without regeneration; necessary resolution preserves seeded
compatible versions. Candidate validation and target-library verification precede
official lock replacement. CLI preview fixes are tracked in refactor 028.

Validation on Windows, R 4.5.2 (2026-10-12): the full testthat suite passed
174 test cases and 527 assertions, with zero failures, errors, test warnings or
skips. This includes real add/remove and sync integration runs, plus 25 focused
contract cases covering resolver, source, failure and preservation behavior.
R CMD INSTALL and generated documentation checks passed. The real backend
experiments and their limitations are recorded in the capability matrix.

Cross-platform restore CI now targets the uploaded project explicitly and checks
that restoration preserves lock bytes. Those hosted jobs still require a remote
run. A general archive search for upper-bound constraints remains unimplemented;
exact historical versions are supported and incompatible resolutions fail before
the official lock is replaced. Further feature work belongs to stage E.

## Resolver provenance adaptation

A real cache experiment preserved R6 2.5.1 while adding glue, but the cached
binary carried the build server's RSPM repository name under a CRAN declaration.
The adapter now creates and installs the same pak resolution lock. Candidate
normalization accepts an otherwise unknown alias only when that installed plan
records the same package version and an unambiguous download URL under a
declared repository. This records resolution provenance, not the binary build
server's identity. Conflicting existing evidence is never overwritten.

Prune-only snapshots also preserve verified URL evidence from unchanged seeded
lock identities, since installed DESCRIPTION metadata can omit that evidence.
Changed roots and contradictory/new evidence are excluded from this fallback.
Regression tests cover both resolver-backed aliases and seed-only provenance.

## Explicit restore engine

The full Windows integration run stalled after the candidate had been written,
inside restoration with the project's ambient renv/pak integration enabled.
Intent already uses pak explicitly for resolution. Its restore adapter will
temporarily set the documented renv.config.pak.enabled option to FALSE so native
renv transactional restore executes the selected lock without delegating back
to pak. Restore the caller's option on success and failure; test both paths.
This removes an ambient engine choice from the workflow contract without changing
the project's user-level engine preference.

Native restore exposed a second cache boundary: a cached package can have a
known URL contradicting the candidate's selected repository. The adapter will
translate repository identities to explicit URLs in a temporary restore lock,
use strict restore with latest-version retry disabled, and allow one targeted
cache-bypassing rebuild for observed source drift. Verification still gates the
official commit; failures do not relax source identity.

The reproduction confirmed that renv considers the installed version synchronized
even with rebuild requested. For source drift only, remove the affected project
library entries through renv before retrying, and disable both cache reuse and
user/site-library installation shortcuts during that retry. Restore all caller
options afterward. A failed retry may leave those entries absent; retain the
official lock and report the existing sync recovery instruction.
