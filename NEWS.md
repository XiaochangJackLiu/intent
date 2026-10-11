# intent 0.0.1

* CLI preview safety: reject conflicting `adopt --apply --dry-run` and
  `sync --json` without `--dry-run` before dispatch. Print action plans for
  ordinary add/remove/sync previews. Options previously accepted but ignored
  by a command now produce an explicit error; missing option values cannot
  consume another option.
* Initial CRAN release.
* `init()` — initialise an intent project with declarative repository policy.
  DESCRIPTION-first classification and safety gates prevent accidental mutation
  of existing renv projects.
* `adopt()` — migrate an existing R project into intent management with
  dry-run preview and `"manifest"` / `"lockfile-assisted"` strategies.
* `add()` / `remove()` — manage dependencies in `DESCRIPTION` and `renv.lock`.
* `sync()` — restore the project library from the lockfile.
* `status()` — report drift between manifest, lockfile, and library.
* `verify()` / `doctor()` — check the project contract without changing state.
  New checks: platform-specific repository URL detection, lockfile repository
  resolvability against declared `Config/intent/repos/` entries.
* CLI entry point (`intent`) for all commands.
* URL-first repository provenance matching.
* Environment variable `INTENT_DEFAULT_REPOS` for custom default repositories.
* Dynamic base R package detection from the R installation.
* Cross-platform lockfile verification CI pipeline.

- Sync now stages required dependency resolution, validates candidate locks, and
  commits them only after restoration and library verification succeed.
- Compatible locks are restored without rewriting. Version/source drift appears
  in status and verification; informational and warning issues do not fail verify.
- Initialization and adoption share reconciliation, and tool lifecycle is explicit.
- Historical upper-bound archive search remains a documented resolver limitation.
