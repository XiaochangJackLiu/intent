# Refactoring Plans

This directory contains implementation-level plans for refactoring work.
Each refactor should be documented before code changes begin, reviewed as a
plan, and updated after implementation with the actual result.

## Workflow

1. Create a new document from [000 Template](000-template.md).
2. Scope the document to one architectural concern.
3. Mark the document as `planned`.
4. Review and revise the plan before implementation.
5. During implementation, mark the document as `in-progress` if useful.
6. After implementation, mark it as `implemented` and fill in the result notes.
7. If the plan is replaced by another approach, mark it as `superseded` and link
   to the replacement.

## Status Values

- `planned`: accepted as the intended direction, but not yet implemented.
- `in-progress`: implementation has started.
- `implemented`: implementation is complete and the result section has been
  updated.
- `superseded`: the plan was replaced by another plan or decision.

## Rules

- Every refactor must have a plan document before code changes.
- Each document should cover one concern, not a full roadmap phase.
- Implementation should follow the accepted plan unless the plan is updated
  first.
- The result section should record what actually changed, even if the final
  implementation differs from the original plan.

## Plans

- [001 Explicit Project Resolution](001-explicit-project-resolution.md)
- [002 Backend Boundary](002-backend-boundary.md)
- [003 Command Layer](003-command-layer.md)
- [004 Status and Dry Run](004-status-and-dry-run.md)
- [005 CLI Entry Point](005-cli-entry-point.md)
- [006 Dependency Override Validation](006-dependency-override-validation.md)
- [007 CI Quality Gates](007-ci-quality-gates.md)
- [008 Sync Prune Behavior](008-sync-prune-behavior.md)
- [009 Init Default Repository](009-init-default-repository.md)
- [010 JSON Machine-Readable Output](010-json-machine-readable-output.md)
- [011 Override User Documentation](011-override-user-documentation.md)
- [012 Smaller Improvements](012-smaller-improvements.md)
- [013 Renv Boundary Cleanup](013-renv-boundary-cleanup.md)
- [014 CLI Design Document Update](014-cli-design-doc-update.md)
- [015 Layering Cleanup](015-layering-cleanup.md)
- [016 Testing Plan and Coverage Analysis](016-testing-plan.md)
- [017 Intent Bootstrap Lifecycle](017-intent-bootstrap-lifecycle.md)
- [018 Repository Policy](018-repository-policy.md)
- [019 CI Platform Failures on macOS ARM64](019-ci-platform-failures.md)
- [020 URL-First Repo Matching](020-url-first-repo-matching.md)
- [021 Dehardcode Constants](021-dehardcode-constants.md)
- [022 Init DESCRIPTION-First Safety](022-init-description-first-safety.md)
- [023 Bootstrap Dependency Planning](023-bootstrap-dependency-planning.md)
- [024 Adopt Migration Plan](024-adopt-migration-plan.md)
- [025 Bootstrap Plan User-Facing Output](025-bootstrap-plan-ux.md)
- [026 Init Classification Hardening](026-init-classification-hardening.md)
