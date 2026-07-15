# Repository Name Mapping: CRAN vs RSPM

## Problem

When a user declares a repository in `Config/intent/repos/CRAN` pointing to
Posit Package Manager (PPM), the `renv.lock` file may contain the repository
name `RSPM` instead of `CRAN`. This is because **PPM's PACKAGES file always
reports `Repository: RSPM`**, regardless of how the user names the repository
in their `DESCRIPTION` file.

## How intent resolves this

`intent` uses **URL-aware matching** rather than name matching to resolve
repository identities. The matching protocol has three levels, tried in order:

1. **Direct name match** — if the lockfile's `Repository` field matches a name
   in `Config/intent/repos/`, it passes immediately.
2. **URL match via package record** — if the lockfile record carries its own URL
   metadata (e.g., `RepositoryURL`, `RemoteUrl`), both URLs are normalised and
   compared.
3. **URL match via lockfile `$R$Repositories`** — the lockfile's repository
   table is used to resolve the name to a URL, which is then compared against
   declared repository URLs.

During `intent::snapshot()`, `intent_supplement_repositories()` scans package
records for repository names (like `RSPM`) that are not in the lockfile's
`$R$Repositories` table. When a match is found via URL, the name is added to
the table so `renv::restore()` can resolve all packages.

The declared repository names always take precedence; supplemented names are
preserved alongside them.

## What this means for users

- You can name your repository whatever you like in `Config/intent/repos/`
  (e.g., `CRAN`, `PPM`, `MY_COMPANY_CRAN`).
- `intent` will match packages installed from PPM regardless of the name you
  choose.
- `renv::restore()` will be able to resolve all packages because both your
  declared name and `RSPM` are present in the lockfile's repository table.

## Example

DESCRIPTION:
```
Config/intent/repos/CRAN: https://packagemanager.posit.co/cran/latest
```

After `intent::add("dplyr")`, the lockfile will contain:
```json
{
  "R": {
    "Repositories": {
      "CRAN": "https://packagemanager.posit.co/cran/latest",
      "RSPM": "https://packagemanager.posit.co/cran/latest"
    }
  },
  "Packages": {
    "dplyr": {
      "Repository": "RSPM"
    }
  }
}
```

Both names point to the same URL. `renv::restore()` finds `RSPM` in the
repository table and resolves `dplyr` correctly.
