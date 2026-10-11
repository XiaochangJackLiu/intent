lib <- normalizePath(file.path("sandbox", "bootstrap-library"), winslash = "/")
.libPaths(c(lib, .Library), include.site = FALSE)
Sys.setenv(
  R_LIBS_USER = lib,
  R_USER_CACHE_DIR = file.path(lib, ".cache"),
  RENV_PATHS_ROOT = file.path(lib, ".renv"),
  RENV_CONFIG_AUTOLOADER_ENABLED = "FALSE"
)
dir.create(
  Sys.getenv("R_USER_CACHE_DIR"),
  recursive = TRUE,
  showWarnings = FALSE
)
project <- tempfile("intent-capability-")
dir.create(project)
writeLines(
  c("Package: capability", "Version: 0.0.1", "Imports: glue (<= 1.8.0)"),
  file.path(project, "DESCRIPTION")
)
options(repos = c(CRAN = "https://cloud.r-project.org"))
lock <- file.path(project, "pak.lock")
error <- tryCatch(
  {
    pak::lockfile_create(
      paste0("deps::", project),
      lockfile = lock,
      lib = lib,
      upgrade = FALSE,
      dependencies = NA
    )
  },
  error = function(e) e
)
stopifnot(
  inherits(error, "error"),
  grepl("Could not solve", conditionMessage(error), fixed = TRUE)
)
cat(
  "PASS: pak rejects an unavailable upper-bound candidate rather than relaxing it\n"
)
