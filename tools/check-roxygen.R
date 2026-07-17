#!/usr/bin/env Rscript
# Pre-commit hook: verify that roxygen2 documentation is up to date.
# Runs roxygenise() and fails if man/ or NAMESPACE have uncommitted changes.

args <- commandArgs(trailingOnly = TRUE)
project_dir <- if (length(args) > 0) args[[1]] else "."

if (!requireNamespace("roxygen2", quietly = TRUE)) {
  message("roxygen2 not installed, skipping check")
  quit(status = 0)
}

old_dir <- setwd(project_dir)
on.exit(setwd(old_dir))

# Re-generate documentation
message("Running roxygen2::roxygenise() ...")
roxygen2::roxygenise(roclets = c("collate", "namespace", "rd"))

# Check for changes in generated files (tracked and untracked)
diff_status <- system2("git", c("diff", "--exit-code", "man/", "NAMESPACE"))
untracked <- system2("git", c("ls-files", "--others", "--exclude-standard", "man/"),
                     stdout = TRUE)
untracked_ns <- system2("git", c("ls-files", "--others", "--exclude-standard", "NAMESPACE"),
                        stdout = TRUE)

has_untracked <- length(untracked) > 0 && any(nzchar(untracked))
has_untracked_ns <- length(untracked_ns) > 0 && any(nzchar(untracked_ns))

if (diff_status != 0 || has_untracked || has_untracked_ns) {
  cat(
    "\n---\n",
    "ERROR: roxygen2 documentation is out of date.\n",
    "man/ or NAMESPACE changed after running roxygenise().\n\n",
    "Run the following and commit the result:\n",
    "  Rscript -e 'roxygen2::roxygenise()'\n",
    "  git add man/ NAMESPACE\n",
    "---\n",
    sep = "",
    file = stderr()
  )
  quit(status = 1)
}

message("roxygen2 documentation is up to date.")
quit(status = 0)
