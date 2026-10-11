# User-Facing Workflow Contracts

Date: 2026-10-11
Status: sync resolution policy accepted; implementation defaults and limitations recorded in refactor 029 and the backend capability matrix

## Authority and scope

The accepted [product boundary](06-product-boundary.md) establishes intent as a
dependency contract and workflow tool. This draft proposes concrete verb
semantics for stage B of [the next-step plan](07-next-steps.md).

Existing documentation describes shipped behavior with known inconsistencies.
Only the sync resolution policy below has been accepted by the user. Other semantics originated as proposals; the implementation defaults below are recorded in refactor 029. The later [capability assessment](09-backend-capability-matrix.md) records tested backend behavior and remaining gaps.

## Terms and proposed common rules

- **Declared intent:** dependencies, constraints, sources and policy in
  DESCRIPTION/Config/intent. User-authored intent is not inferred from local
  installations.
- **Resolved state:** exact package identities and their dependency closure,
  currently recorded in renv.lock.
- **Installed state:** what the explicitly selected project library contains,
  including versions and available provenance.
- **Restore:** install the resolved identities without selecting newer versions.
- **Resolve:** select a dependency closure satisfying declared intent and policy.

Proposals for all workflows:

1. CLI and R API invoke the same product workflow and target an explicit project.
2. Validation and planning precede mutation. A preview explains changes and
   identifies uncertainty; it does not install, remove or write project state.
3. Compatible locked identities are preferred. Local library drift does not
   authorize updating declared intent or deriving a new lock from that drift.
4. Source policy is checked before restoration as well as new installation.
   Tightening policy must not silently switch a package to an unrelated source.
5. Required resolved-state changes use a validated candidate before replacing
   the official lockfile. An invalid candidate leaves the old lockfile intact.
6. Do not report success without checking the verb's postconditions. If source
   identity cannot be established, surface that limitation rather than claim
   a verified match.
7. Errors explain completed changes, remaining work and how to recover. Full
   rollback of library changes is not promised before backend evaluation.

Exact manifest/lockfile commit timing and recovery behavior remain to be
specified with stage-C evidence. A candidate lockfile rule alone is not a
transaction covering every file and installed package.

## Proposed verb boundaries

| Verb | User purpose | Allowed intent changes | Resolved/installed-state effects | Success condition |
| --- | --- | --- | --- | --- |
| init | Establish a managed project | Create new intent; add agreed metadata to a compliant manifest while preserving user constraints | Provision backend support as needed; resolve/restore only the agreed initialization scope | Required project metadata exists; initialized state meets the declared initialization scope |
| adopt | Bring an existing project's declarations under intent management | Only reviewed migration changes; candidates never become declarations implicitly | Only backend actions represented in the migration plan | Applied changes match the plan; stated post-adoption checks pass |
| add | Declare a direct dependency and reconcile state | Add/update the requested declaration; preserve unrelated declarations | Resolve affected closure and restore it; retain compatible existing locks where possible | Requested dependency is declared, resolved and installed consistently |
| remove | Remove direct dependency intent and reconcile state | Remove requested declaration and its associated override where applicable | Recompute retained closure; remove only packages no longer required | Removed dependency is no longer direct intent; all remaining dependencies still work |
| sync | Bring state into agreement with current intent | None | Restore a valid lock; resolve only when required by changed/missing state under the selected sync policy | Required closure satisfies intent, policy and installed-state checks |
| status | Explain drift and relevant next actions | None | Read-only | Returns structured observations, including uncertainty |
| verify/doctor | Check the dependency contract | None | Read-only | ok means no blocking errors; warnings/info remain visible |

Initialization scope is still a decision: init may prepare only management
infrastructure or also synchronize all declared dependencies. Either choice
must be visible and must not masquerade as the other. Environment activation
and caching remain adapter mechanisms rather than new product responsibilities.

## Sync: accepted resolution policy

On 2026-10-11 the user selected: **automatically resolve necessary dependencies
when changed DESCRIPTION is no longer satisfied by the lockfile, preserving
compatible locked versions where possible**. This settles necessary resolution
versus restore-only sync for changed declarations. The recommended operating
model is restore valid locked state and avoid opportunistic upgrades.

Restore-only sync was not selected for changed declarations. The detailed
missing/corrupt lock, source-policy, pruning and failure rules in the following
table remain proposals unless separately decided. This does not introduce
`lock` or `update` as implemented commands.

| Scenario | Proposed behavior under the accepted sync direction | What must stay unchanged |
| --- | --- | --- |
| Valid lock, matching library | Validate policy and contract; no-op | DESCRIPTION and lockfile |
| Valid lock, empty library | Restore exact locked identities | DESCRIPTION and lockfile |
| Valid lock, wrong installed version | Replace the wrong installation with the locked identity | DESCRIPTION and lockfile |
| No lockfile | Resolve declared intent, validate candidate and establish installed state | DESCRIPTION |
| New direct dependency | Resolve the necessary closure, retain compatible locked identities, validate candidate and restore | Unrelated declarations |
| Changed version constraint excludes locked version | Resolve a compatible version and necessary dependency changes | DESCRIPTION |
| Constraint changes but existing lock remains valid | Revalidate; no dependency upgrade solely because text changed | Locked identities unless another requirement forces change |
| Same version requested from a different source | Treat identity as changed; resolve/restore required provenance | Unrelated declarations |
| Removed direct dependency still required transitively | Retain it as a transitive dependency | Remaining dependency closure |
| Removed dependency becomes an orphan | Prune by default, subject to the prune contract below | Remaining dependency closure |
| Existing source now forbidden by policy | Stop before mutation with an explanation | DESCRIPTION, lockfile and library |
| Unreadable or internally corrupt lockfile | Stop and explain the problem; do not silently discard it | Existing project state |

Missing lockfiles and corrupt lockfiles are distinct states. Source changes
explicitly declared by the user differ from a policy change that merely
forbids an old source; the latter does not identify an authorized replacement.

An empty local library is never evidence that the lock should become empty.
An installed version newer than the lock is drift, not permission to snapshot
it as the new resolved state. A successful restore-only operation should not
rewrite the lockfile merely because the current OS or R session differs.
Required compatibility checks must run before restore; their exact platform/R
rules remain to be settled with the verification contract and backend evidence.

### Proposed prune semantics

Default prune removes true orphans, not every package absent from the list of
direct dependencies. Removing a direct declaration does not remove a package
still reachable through another dependency.

Recommend that prune=FALSE preserves unrelated extra lock/library entries even
when new dependencies are added. This is a compatibility choice requiring
confirmation and backend evidence; retained extras must be reported separately
from the managed closure and must not bypass source policy. Verification must
distinguish those extras from missing/incorrect required dependencies.

Whether retained extras are warnings or blocking contract errors, and whether
retention policy needs durable representation, remain open. Do not add new
Config fields solely to settle this before evaluating the actual workflows.

## Add and remove examples

- Adding a new package may update transitive dependencies when necessary, but
  must not upgrade every other compatible package by default.
- Re-adding an existing package must not silently replace its exact pin or
  source with an installed-version lower bound. Explicitly requested changes
  should appear in the plan. The default constraint for a newly added package
  remains a decision; the current >= installed-version behavior is not adopted
  automatically by this draft.
- Removing A while B still requires A removes A's direct declaration, retains
  A in the resolved/installed closure and explains why it remains.
- Removing an undeclared package must not delete it from the library merely
  because the user supplied its name. Choose a clear no-op or input error;
  arbitrary uninstall is outside remove's dependency-intent purpose.
- An override source/version must satisfy ordinary declared constraints. A
  conflict is an input error, rather than an undocumented precedence rule.

## Init and adopt decisions still needed

- Keep init conservative about existing non-compliant manifests and renv state
  without declared intent. Migration belongs to adopt.
- An adoption plan must include configuration, tool hydration, lockfile and
  library effects, not only DESCRIPTION edits. install_self must affect the
  preview when it affects execution.
- Recommend preserving user bootstrap constraints by default and reporting
  conflicts. Overriding them should require an explicit, visible operation.
  This conflicts with the later override=TRUE decision in refactor 024 and
  needs an explicit replacement decision, not a silent implementation change.
- Define the default repository and empty-default behavior consistently.
- Interactive candidate selection remains a potential feature; do not promise
  a prompt while confirm/strategy parameters do not implement it.

## Status and verification proposals

Status should compare direct declarations, required resolved closure and
installed identities, reporting missing packages, constraint violations,
version/source drift, orphans and insufficient provenance separately. A normal
transitive dependency is not an orphan merely because it is not directly listed.

Verification should use the same identity/policy rules as planning and execution:

- Errors block success; warnings/info remain visible but do not set ok=FALSE.
- R constraints compare full versions. A compatible difference between session
  and locked R may be informational; genuine incompatibility is an error.
- Repository aliases are acceptable only when supported by matching declared
  URL evidence. Resolve names consistently across provenance and resolvability
  checks. The permitted lockfile representation still needs a decision.
- mode=off disables source allowlist enforcement, not all validity checks.
  Keep platform URL risks visible as warnings, consistent with refactor 027.
- Bootstrap tool exemptions and install_self=never must not make a deliberately
  external tool an unexplained verification failure. Define which tools belong
  to the managed closure and which are execution prerequisites.

## Preview completeness and capability limits

Plans should describe intended manifest edits, resolution needs, known package
changes, configuration effects, removals and validation failures. Unknown
versions or transitive changes must be labeled unresolved, not fabricated.

Whether a fully resolved preview requires network access or cache writes is a
backend-evaluation question. At minimum, previews must leave project files and
the installed library unchanged. Any permitted external cache effects need a
separate documented decision. Preview output is not yet a saved executable
artifact and must not imply it remains valid after project state changes.

## Decisions before semantic implementation

1. Sync policy selected: necessary resolution for changed declarations,
   preserving compatible locked versions where possible. Settle the remaining
   scenario rules, especially missing/corrupt lockfiles and source-policy changes.
2. Decide initialization scope and whether explicit update/resolution verbs
   are needed.
3. Decide new dependency constraint defaults, override conflicts and bootstrap
   constraint migration behavior.
4. Decide prune=FALSE and verification treatment of retained extras.
5. Decide repository defaults, aliases and permitted lockfile representation.
6. Decide external tool lifecycle, full-version verification and partial-failure
   reporting with capability evidence.

## Acceptance scenarios for backend evaluation

Use independent fixtures for: restore into an empty library without changing a
valid lock; replace an installed wrong version; resolve a new constraint while
retaining unaffected locks; change same-version source identity; preserve a
removed direct dependency that remains transitive; reject a forbidden existing
source before mutation; reject an invalid candidate without replacing the lock;
preserve extras under the chosen no-prune policy; and restore a lock on another
OS. Record the exact package/backend versions and observable side effects.

## Current implementation profile

Refactor 029 implements the central policy with these explicit defaults:
init reconciles all declared dependencies; adopt preserves constraints and
previews backend effects; missing locks resolve and corrupt locks stop;
prune removes orphans while no-prune retains extras; errors fail verify but
warnings/info do not. Managed/external intent lifecycle is recorded explicitly.
The proposal questions above remain historical design context; refactor 029 and
the capability matrix describe the implemented profile and its limitations.
