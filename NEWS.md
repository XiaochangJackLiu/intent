# intent 0.0.1

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
