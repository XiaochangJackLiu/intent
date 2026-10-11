# Backend Capability Assessment

Date: 2026-10-11
Status: evaluated on Windows, R 4.5.2; cross-platform execution delegated to CI

Intent owns dependency contracts and user workflows. The current implementation
retains renv and pak behind explicit adapters; this assessment does not commit
the product to their complete capabilities.

| Capability | Evidence | Decision |
| --- | --- | --- |
| Project library path and infrastructure | renv 1.3.1 public paths/init APIs, bare initialization without an intent snapshot | Retain behind backend adapters |
| Restore explicit lock into explicit library | Real glue restore into empty project library, followed by identity checks | Retain; transactional restore is a library operation, not a cross-file transaction |
| Candidate snapshot | Real snapshot from a temporary library with explicit roots and lock path | Retain; validate and normalize before target restore |
| Compatible lock restoration | Three real constraint scenarios restored after deleting the target library; official lock bytes unchanged | Retain; avoid snapshot on a compatible lock |
| Resolve current repository candidates under DESCRIPTION constraints | pak 0.11.1 deps:: synthetic DESCRIPTION; lower/exact/upper constraints at glue 1.8.1 passed | Adapt: preserve manifest constraints and stage compatible locked records |
| Reject an unsatisfied historical upper constraint | Real glue <= 1.8.0 solve failed while current candidate was 1.8.1 | Safe failure; pak does not automatically search all archived versions |
| Explicit historical exact version | Real historical R6 == 2.5.1 resolved, built, restored and verified through package@version Remotes | Adapt; validate the returned candidate before use |
| Source and repository policy | Intent unit tests cover old URL records, table-backed aliases, same-version source changes and policy tightening | Intent-owned; renv's ability to download is not policy authorization |
| Self-tool lifecycle | External/managed selection recorded in DESCRIPTION; hydration uses available local sources | Intent-owned; no invented remote source for intent |
| Cross-platform portability | CI now restores Linux-produced locks on macOS and Windows, then verifies and compares bytes | Pending remote run; local Windows tests do not prove all platforms |

## Resolver boundary

The backend may fail when no candidate is available under its current metadata.
It must never silently relax an upper/exact constraint. Full historical-version
search and multi-package backtracking are not implemented here. Users can supply
an exact dependency/override or a declared repository snapshot that offers the
required version. An unresolved contract is an error and leaves the official
lock intact; replacing this resolver capability remains a follow-up product
decision.

Compatible locked records are staged as preferences. The solver can replace
them when the new dependency graph requires it. This is not a guarantee that
every compatible package remains fixed under every transitive constraint.

## Public API sources

- [pak package sources](https://pak.r-lib.org/reference/pak_package_sources.html)
- [pak lockfile creation](https://pak.r-lib.org/reference/lockfile_create.html)
- [pak package history](https://pak.r-lib.org/reference/pkg_history.html)
- [renv restore](https://pkgs.rstudio.com/renv/reference/restore.html)
- [renv snapshot](https://pkgs.rstudio.com/renv/reference/snapshot.html)

Repeatable local evidence lives in sandbox/evaluate-reconcile.R and
sandbox/evaluate-backend.R. Package unit tests cover the workflow decisions
independently of network availability.

## Cached binary provenance

The R6/glue experiment reproduced a cached binary retaining RSPM build metadata
under a cloud CRAN declaration. The adapter now uses pak lockfile_create and
lockfile_install as one resolved plan. A matching version plus an unambiguous
declared download URL can substantiate the candidate's repository alias.
Unknown or contradictory evidence remains visible; alias names alone are never
enough. The corrected experiment preserved historical R6 while adding glue and
passed verify.

[Public pak lockfile installation API](https://pak.r-lib.org/reference/lockfile_install.html)

The restore adapter explicitly selects native renv restoration for each call
and restores the caller's configuration afterward. This avoids re-entering
pak through ambient renv integration after pak has already resolved the candidate.
Both success and failure option restoration are unit-tested.
[renv's documented configuration precedence](https://pkgs.rstudio.com/renv/reference/config.html)

Native restore can also encounter a known cached origin that contradicts the
candidate repository. Restore transport records use explicit repository URLs,
strict matching and no latest-version retry. Observed source drift receives at
most one targeted rebuild. That retry removes only affected project-library
entries and temporarily disables both renv cache reuse and user/site-library
installation shortcuts. This is necessary because renv otherwise reports an
identical version as synchronized despite conflicting source metadata. The
final identity check still decides success; failure retains the official lock.
[renv installation shortcut configuration](https://pkgs.rstudio.com/renv/reference/config.html)
