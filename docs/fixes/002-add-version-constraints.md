# Version Constraints in `intent::add()`

## Behaviour

`intent::add("pkg")` records the **installed version** as a `>=` lower-bound
constraint in `DESCRIPTION`. For example, if `dplyr` 1.1.4 is installed:

```
Imports:
    dplyr (>= 1.1.4)
```

This means the project declares it needs at least the version that was
resolved at `add()` time. `renv.lock` still pins the exact version for
reproducibility.

## Why `>=` and not an exact version?

The `DESCRIPTION` file expresses **intent** (what you want), while `renv.lock`
expresses **state** (what you have). A lower bound in `DESCRIPTION` says
"this project needs at least version X" without preventing upgrades. The
lockfile provides the exact reproducibility guarantee.

## Pinning stricter versions

For stricter version constraints (exact versions, upper bounds, or specific
sources), use **Dependency Overrides** in `DESCRIPTION`:

```
Config/intent/Imports/dplyr: dplyr@1.1.4@cran
Config/intent/Imports/pkg: user/repo@0.2.0@github
```

See the [Dependency Overrides](../../README.md#dependency-overrides) section in
the README for the full syntax.

## Passing `@version` to `add()`

The `@version` suffix in `add("dplyr@1.0.0")` is **silently stripped** —
only the package name is used. To pin a specific version, use dependency
overrides instead.
