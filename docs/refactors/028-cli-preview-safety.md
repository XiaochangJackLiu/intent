# CLI Preview Safety and Output

Status: `implemented`
Date: 2026-10-11

## Problem

Review findings 1 and 8 identify two immediate contract violations: conflicting
adopt flags dispatch mutation, and ordinary CLI dry-run does not display the
returned plan. Shared parsers also accept flags that command handlers ignore.

## Goal

Reject unsupported or contradictory CLI input before command dispatch, and
display the existing plan objects for supported preview commands. Preserve
the existing R API and backend workflows in this slice.

## Non-Goals

- Do not change sync resolution/restoration semantics.
- Do not implement new JSON support for add/remove or new init preview support.
- Do not replace renv/pak, redesign plan objects or add plan persistence.
- Do not implement a complete transactional workflow or adoption confirmation.

## Current State

- `cli_collect_repos()` parses apply/dry_run, but `cli_adopt()` derives execution
  solely from apply. Both flags together dispatch `dry_run = FALSE`.
- `cli_add()` and `cli_remove()` do not print plans. `cli_sync()` prints JSON
  previews only. `intent_cli()` returns invisibly under Rscript.
- The two shared parsers accept flags across commands; handlers silently ignore
  several flags. `sync --json` without preview still executes sync.
- Core printers and JSON serialization already exist and should be reused.

## Proposed Design

Validate flag applicability at the CLI boundary before any cmd_* call. Shared
parsers may remain shared, but must know which flags are allowed or preserve
explicitly supplied flag names for validation. Do not infer supplied flags from
boolean defaults: explicit unsupported flags must be rejected even if false.

Supported options for this slice:

| Command | Allowed options |
| --- | --- |
| init | --repo, --yes, --no-default-repo |
| add | --project, --dev, --dry-run |
| remove | --project, --dry-run |
| sync | --project, --dry-run, --json, --prune, --no-prune |
| status | --project, --json |
| verify/doctor | --project, --json |
| adopt | --project, --repo, --strategy, --apply, --dry-run, --json, --yes |

Preserve currently supported positional arguments and repeatable repositories.
Preserve current prune flag order semantics; changing that behavior is outside
this fix. Per-command help behavior is also outside scope.

Rules:

1. Reject adopt --apply together with --dry-run in either order. Error:
   `--apply and --dry-run cannot be used together.`
2. Without --apply, adopt remains preview-only, including when explicit
   --dry-run is present. --yes changes prompting, not execution mode.
3. Reject sync --json without --dry-run before cmd_sync is called. Error:
   `--json requires --dry-run for intent sync.`
4. Reject unsupported options with an error naming the command and option.
   Reject a missing option value when another --option follows it; otherwise
   a preview flag could be swallowed as a project/strategy/repository value.
5. Call the command once. For add/remove/sync previews, print the returned plan
   for human output; use existing serialization for supported JSON output.
6. Preserve invisible results at the top-level CLI entry point. Output must
   come from explicit rendering, not automatic R printing.
7. Do not mix human plan text into JSON stdout; diagnostic/progress messages
   can remain on stderr. Preserve supported status/verify/adopt JSON behavior.

Compatibility change: inputs previously accepted but ignored now fail clearly.
Document this in NEWS and CLI docs. The supported JSON commands above resolve
the current ambiguous common-flags sentence suggesting add/remove JSON support.

## Implementation Steps

1. Add CLI flag applicability validation using a small helper or parser input;
   choose the simplest implementation that handles explicit flags reliably.
2. Add adopt conflict and sync JSON prerequisite checks before dispatch.
3. Render dry-run plans explicitly in add/remove/sync handlers.
4. Update CLI command shapes/help, stage-A behavior documentation and NEWS.
   Do not publish the separate workflow draft as implemented behavior.
5. Add focused regression coverage and update the historical audit probes so
   they no longer assert fixed defects. Keep the dated audit as a record and
   append resolution notes with test evidence.

## Test Plan

Tests use command-boundary spies/stubs, without real package operations:

- Both adopt conflict orders fail and cmd_adopt is never called.
- Adopt default/--dry-run dispatches preview; --apply dispatches execution;
  --yes alone remains preview-only.
- Sync --json alone fails with zero cmd_sync calls.
- Actual intent_cli entry-point calls print readable add/remove/sync plans,
  including the planned action text; results are still returned invisibly.
- sync --dry-run --json remains parseable JSON with no human plan text.
- Unsupported flags fail before dispatch: add --json, remove --dev,
  status --dry-run, verify --no-prune, init --apply, init --dry-run and
  adopt --no-default-repo. Check doctor through the verify handler.
- Existing valid flag combinations still dispatch correct parameters once;
  repeated repo flags and prune order behavior are preserved.

Use testthat with the project's existing mockery conventions. If dependencies
are unavailable, a dependency-free CLI dispatch harness can provide interim
evidence, but it must not be represented as a full package test run.

## Acceptance Criteria

- Contradictory preview/execution flags cannot dispatch mutation.
- All three ordinary CLI dry-run paths display plans under the real entry point.
- Supported JSON behavior remains machine-readable.
- Unsupported flags are errors, not silent no-ops.
- No changes to public R API signatures or backend execution semantics.
- Focused CLI tests pass; validation limitations and documentation updates are
  recorded accurately.

## Result / Follow-Up Notes

- Result: Added command-specific allowed options to shared CLI parsers,
  adopt execution/preview conflict rejection, sync JSON prerequisite checking,
  explicit preview printing and option-value validation. Updated CLI help,
  public CLI documentation, NEWS and the historical review's resolution notes.
  Added seven focused testthat regression cases in test-cli-preview.R and a
  dependency-free CLI boundary harness in sandbox/check-cli-preview.R.
- Validation: 53 offline CLI boundary assertions passed under R 4.5.2. After
  installing isolated test dependencies, all seven focused testthat cases also
  passed, including real jsonlite serialization. Stage B–D validation and real
  backend installation evidence are recorded in refactor 029.
- Follow-up: Workflow plan completeness and backend changes belong to stages
  B–D of [the next-step plan](../07-next-steps.md).
