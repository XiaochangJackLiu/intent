# Product Boundary and Backend Evaluation

Date: 2026-10-11
Status: accepted product direction; backend capability evaluation pending

## Decision

At this stage, intent is a user-facing dependency contract and workflow tool.
It defines the verbs users invoke and the guarantees those verbs provide.
Environment management is a separate responsibility accessed through backend
adapters.

This decision clarifies the product boundary in documents 01, 02 and 04. It
does not prescribe a complete replacement for renv, commit to retaining all of
renv, or change existing command behavior before a documented implementation
plan is accepted.

## What intent owns

- Dependency intent in DESCRIPTION, including version constraints and sources.
- Repository and source policy in Config/intent/.
- The meaning, inputs, outputs and side effects of user-facing verbs.
- Planning and explaining changes before execution.
- Comparing declared intent, resolved state and installed state.
- Validating backend results against the dependency contract.

The current verbs are init, adopt, add, remove, sync, status and verify/doctor.
Their presence is not proof that their contracts are complete. The review in
`review-2026-10-11.md` records implementation gaps and conflicting statements.
New verbs and changes to existing semantics need their own design decisions.

## What environment backends provide

Mechanisms such as project library creation, isolation, activation, caching,
package installation and restoration are backend responsibilities. intent may
coordinate these mechanisms when a user workflow needs them, but it does not
need to own their implementations.

Backend concepts should not dictate the public verbs. A user workflow may
require several backend operations; a backend operation such as snapshot is
not automatically a user-facing command or the authority on desired state.

The current implementation uses renv and pak and records resolved state in
renv.lock. These are implementation and compatibility facts, not requirements
that all future workflows must adopt their defaults or session behavior. This
decision does not authorize a lockfile format migration or define a new format.

## How to decide what remains in renv

Evaluate individual capabilities against intent's workflow contracts. Retain
the mechanisms that satisfy those contracts; replace the parts that cannot.
Do not weaken a user-facing guarantee merely to match renv's behavior.

The next design and evaluation pass should proceed in this order:

1. Specify each verb's preconditions, inputs, expected state, side effects and
   failure behavior. Resolve the meaning of sync and its relationship to
   restoring locked state and resolving changed intent.
2. Derive the backend capabilities those workflows require.
3. Inspect the current adapter and the supported public APIs of the installed
   renv version. Record version-specific evidence and validate behavior with
   focused integration experiments.
4. Classify each capability as supported, supported through adaptation, not
   supported, or unresolved. Record side effects and limitations.
5. Write scoped implementation plans for retaining, adapting or replacing
   capabilities, including validation and compatibility consequences.

Evaluation must cover explicit project/library selection, reading installed
versions and provenance, candidate lockfile handling, reproducible restoration,
pruning, and operation without prior session activation. Assess installation
and resolution across the whole renv/pak adapter rather than attributing every
requirement to renv alone.

No capability classification has been completed by this decision. The existing
audit identifies intent implementation problems; it does not establish that
renv itself is incapable of satisfying the affected workflows.

## Immediate scope

Document and evaluate before changing backend implementation. Do not expand
intent into a complete environment manager or build a general multi-backend
framework as a prerequisite. Keep clear, testable boundaries for the workflows
the product actually needs.
