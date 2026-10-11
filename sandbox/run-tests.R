lib <- normalizePath(file.path("sandbox", "bootstrap-library"), winslash = "/")
.libPaths(c(lib, .Library), include.site = FALSE)
Sys.setenv(
  R_LIBS_USER = lib,
  R_LIBS_SITE = "",
  R_USER_CACHE_DIR = file.path(lib, ".cache"),
  RENV_PATHS_ROOT = file.path(lib, ".renv"),
  RENV_CONFIG_AUTOLOADER_ENABLED = "FALSE"
)
dir.create(
  Sys.getenv("R_USER_CACHE_DIR"),
  recursive = TRUE,
  showWarnings = FALSE
)
args <- commandArgs(trailingOnly = TRUE)
results <- testthat::test_local(
  filter = if (length(args)) args[[1]] else NULL,
  reporter = "summary",
  stop_on_failure = TRUE
)
summary <- as.data.frame(results)
cat("Test cases:", nrow(summary), "\n")
print(colSums(summary[intersect(
  c("passed", "failed", "error", "warning", "skipped"),
  names(summary)
)]))
