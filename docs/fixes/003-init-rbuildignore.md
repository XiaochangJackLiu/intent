# `.Rbuildignore` After `intent::init()`

## Why `.Rbuildignore` appears

After running `intent::init()`, you may find a `.Rbuildignore` file in your
project directory containing patterns like:

```
^renv$
^renv\.lock$
```

This file is **not** created by `intent` directly. It is created by
`renv::init(bare = TRUE)`, which `intent` calls internally during
initialisation.

`renv::init()` checks whether the project's `DESCRIPTION` file contains a
`Package` field. Since `intent::init()` always writes a `Package` field
(derived from the directory name), `renv` treats every `intent` project as an
R package and adds `.Rbuildignore` to exclude `renv` infrastructure from
`R CMD build`.

## Is this a problem?

For **R packages**: this is correct and desirable. `renv/` and `renv.lock`
should not be included in the built package tarball.

For **non-package projects** (analysis projects, Shiny apps, etc.): the file
is harmless. It only affects `R CMD build` and has no impact on
`renv::restore()`, `intent::sync()`, or any other `intent` operation.

## Customising

You can edit `.Rbuildignore` to add or remove patterns as needed. `intent`
does not modify this file after initialisation.
