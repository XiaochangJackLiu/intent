# Next Steps: User Workflows and Backend Capability Evaluation

Date: 2026-10-11
Status: stages A–D implemented with unit and local backend evidence; historical archive search remains an explicit capability gap

## Baseline

The accepted [product boundary](06-product-boundary.md) is the basis of this
plan: intent owns user-facing dependency contracts and verbs. Environment
management is delegated through adapters. Retain, adapt or replace renv/pak
capabilities according to the workflows they must support.

The [consistency review](review-2026-10-11.md) supplies the defect inventory.
Its priority order describes impact; the stages below also account for design
and validation dependencies. Do not interpret current implementation defects
as evidence that renv cannot support the desired behavior.

## Execution order

| Stage | Purpose | Deliverable | Completion condition |
| --- | --- | --- | --- |
| A | Contain clear preview/mutation defects | Scoped fix plan, CLI fixes and focused regression tests | Contradictory execution flags cannot mutate; ordinary dry-run displays its plan |
| B | Specify user-facing verb contracts | Workflow contract document and reconciled design references | Each existing verb has explicit inputs, results, permitted mutations and failure behavior; core semantic questions are resolved |
| C | Evaluate backend capabilities | Versioned renv/pak capability matrix and focused experiment results | Each required capability has evidence, classification and a retain/adapt/replace decision, or an explicitly unresolved question |
| D | Implement the dependency contract consistently | Small refactor plans and tested workflow changes | All mutation paths use agreed validation/plan/state rules and report verified outcomes |
| E | Select additional user-facing features | Prioritized feature proposals with acceptance examples | Each selected feature has a user need, bounded scope and demonstrated backend feasibility |

Stages B and C may iterate as experiments reveal limitations, but backend
limitations must not silently redefine the user contract. Stage D decisions
that depend on an unresolved capability must wait for evidence. Independent
defect fixes do not need to wait for the whole backend evaluation.

## A. Immediate preview safety

Write a small plan under `docs/refactors/` before changing implementation.

- Define contradictory flags as an input error: `adopt --apply --dry-run`
  must stop before any mutating command call, regardless of argument order.
- Print plans for CLI add/remove/sync dry-run through the existing plan printer.
- Enforce each command's documented flag applicability, including the current
  rule that sync JSON output requires dry-run.
- Check actual CLI entry-point output and dispatch, rather than relying on
  interactive R's automatic printing.

Acceptance evidence should prove zero mutating calls for rejected/preview
inputs, readable plan output and unchanged supported JSON output. These fixes
do not decide new sync semantics or require replacing environment mechanisms.

## B. User-facing contracts first

Start with sync, then add/remove, init/adopt, and status/verify. For every verb,
specify preconditions, intent read/write behavior, resolved-state behavior,
installed-state behavior, preview output, success criteria and partial-failure
reporting. CLI and R API must share semantics.

Resolve the following questions with concrete before/after examples:

1. **Sync:** when is locked state authoritative for restoration, and when must
   changed DESCRIPTION trigger resolution? What happens with no lockfile, an
   incompatible lockfile, an empty library or a manually changed library?
2. **Updates:** should dependency upgrades be explicit, and do they need an
   `update` verb? Keeping compatible locked versions by default is a proposal,
   not an accepted decision yet.
3. **Constraints and sources:** how do ordinary version constraints and source
   overrides combine? What changes require resolution even at the same version?
4. **Init/adopt:** what is the permitted scope of manifest/config/environment
   changes, and which must appear in the plan? Resolve bootstrap constraint
   preservation versus overriding before implementing migration changes.
5. **Repositories:** resolve declared repository policy, URL aliases and
   lockfile repository-table rules; decide the documented default repository.
6. **Verification:** define blocking errors versus warnings/info, version and
   source consistency, tool exemptions and the meaning of policy mode=off.
7. **Failures:** what may already have changed when installation or validation
   fails? Define lockfile protection and user recovery guidance without promising
   full library rollback before evaluating feasibility.

Use scenarios from the audit as acceptance examples. Reconcile documents 01–04,
relevant refactor decisions and public documentation after decisions are made;
do not resolve contradictions by following current code automatically.

## C. Evaluate renv and pak against those contracts

Create a matrix with one row per required capability and these columns:

`workflow requirement | public API/version | experiment | result | limitations |
supported/adaptable/unsupported/unresolved | proposed implementation owner`

At minimum, evaluate:

- Explicit project/library targets without prior activation or ambient repos.
- Reading installed package versions and source provenance.
- Resolving constraints, source overrides and transitive dependencies through
  the available installer/resolver, including pak where appropriate.
- Restoring existing locked state without deriving new state from an incomplete
  local library first.
- Writing candidate lockfiles, normalizing provenance and protecting the
  official lockfile until validation succeeds.
- Removing true orphans while preserving dependency closure and honoring
  the agreed prune/no-prune contract.
- Predictable failure behavior and the available recovery mechanisms.
- Real cross-platform restore with supported repository URL/alias cases.

Use installed implementation and supported public documentation as evidence;
record exact versions and separate package API limitations from adapter bugs.
The audit environment lacks the test dependencies, so establish an isolated
test library before integration experiments. Obtain external dependencies under
the environment's normal network/approval rules. Do not use the intent project's
dependency files or the user's active library as experiment state.

The output is capability-specific decisions. No complete renv replacement,
new lockfile format or generic multi-backend framework is assumed.

## D. Implement in reviewable slices

After the relevant B/C decisions, write one scoped refactor plan per concern:

1. Dependency/state representation and version/source comparisons, with
   repository matching and verification rules shared where appropriate.
2. Workflow preflight and candidate-lockfile validation on every applicable
   path, including initialization and restoration of existing state.
3. Plan/execution consistency for sync/add/remove, then init/adopt. The plan
   must represent agreed side effects; execution must not silently add others.
4. Final-state checks and accurate success/partial-failure output.
5. Complete the adapter boundary and replace only capabilities shown inadequate.

Do not invent new generic interfaces until the workflows and capability matrix
justify them. Maintain compatibility deliberately; document any changed CLI,
R API or on-disk behavior in the corresponding plan.

For each slice, run focused core/command tests plus real backend integration
tests for the behavior being changed. Restore full package checks when test
dependencies are available. Fix cross-platform CI targeting and add real restore
coverage alongside the changes it validates, rather than waiting until the end.

## E. Feature selection after the baseline

Candidate features, not commitments: explicit dependency updates, explaining
why a package is installed or changing, dependency groups, and interactive adopt
candidate selection. Prioritize them only after the core workflow contracts
and required backend capabilities are known.

Environment creation, activation and cache implementations remain outside the
current product scope. A user workflow may coordinate them through adapters.

## Audit traceability

Numbers refer to the original review findings, not the priority ranks.

| Findings | Planned treatment |
| --- | --- |
| 1, 8: dry-run/CLI flags and output | A; plan consistency completed in D |
| 2: version/source comparison | B constraints and sync decisions → C resolver/state evidence → D |
| 3, 5: policy bypass and direct initialization lockfile writes | B lifecycle rules → C state/restore experiments → D; independent containment fixes may proceed earlier |
| 4: adoption side effects beyond the plan | B adoption contract → C initialization/restore evidence → D |
| 6, 7: verification and repository contradictions | B rule clarification → D core fixes, with C integration evidence where needed |
| 9: cross-platform CI gaps | C/D as part of real restore validation |
| 10: backend calls outside adapter | C owner decisions → D boundary cleanup |

## Immediate next deliverable

Prepared:

- [Stage A scoped fix plan](refactors/028-cli-preview-safety.md), implemented;
  53 offline CLI assertions and seven focused testthat cases passed.
- [Stage B workflow contract draft](08-workflow-contracts.md), with proposals
  and unresolved decisions explicitly separated from accepted product scope.

The user accepted automatic necessary resolution when changed DESCRIPTION no
longer matches the lock, preserving compatible locked versions where possible.
This settles the central sync choice, not every scenario in the workflow draft.

Stages B–D are implemented: missing/corrupt-lock, pruning, initialization,
tool-lifecycle and failure rules now have shared contract enforcement. The stage C
capability matrix records real backend experiments and remaining limitations.
On 2026-10-12, the full suite passed 174 cases and 527 assertions on Windows;
historical exact-version restoration, compatible-version preservation, lower/
exact/upper constraints and unchanged-lock empty-library restoration also passed.
Next: review stage E feature priorities against the settled boundary. Hosted
cross-platform CI still needs to run after push.

## Implementation evidence

See [refactor 029](refactors/029-dependency-contract-enforcement.md) for the
shared reconciliation implementation and test scenarios, and the
[backend matrix](09-backend-capability-matrix.md) for public APIs, actual
experiments and resolver limitations. Additional features remain stage E;
full archived-version search must be decided explicitly before promising it.
