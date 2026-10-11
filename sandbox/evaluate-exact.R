lib <- normalizePath(file.path("sandbox", "bootstrap-library"), winslash = "/")
.libPaths(c(lib, .Library), include.site = FALSE)
Sys.setenv(
  R_LIBS_USER = lib,
  R_LIBS_SITE = "",
  R_USER_CACHE_DIR = file.path(lib, ".cache"),
  RENV_PATHS_ROOT = file.path(lib, ".renv"),
  RENV_CONFIG_AUTOLOADER_ENABLED = "FALSE"
)
pkgload::load_all(".", quiet = TRUE)
project <- tempfile("intent-exact-")
dir.create(project)

writeLines(
  c(
    "Package: capability",
    "Version: 0.0.1",
    "Imports: R6 (== 2.5.1)",
    "Config/intent/repos/CRAN: https://cloud.r-project.org",
    "Config/intent/tools/intent: external"
  ),
  file.path(project, "DESCRIPTION")
)
intent:::cmd_sync(project)
lock <- intent:::backend_read_lockfile(project)
stopifnot(
  identical(lock$Packages$R6$Version, "2.5.1"),
  intent:::cmd_verify(project)$ok
)
cat(
  "PASS historical exact R6 2.5.1
"
)
intent:::intent_set_project_dep(project, "R6", "Imports", ">= 2.0.0")
intent:::cmd_add("glue", project = project)
lock <- intent:::backend_read_lockfile(project)
stopifnot(
  identical(lock$Packages$R6$Version, "2.5.1"),
  intent:::cmd_verify(project)$ok
)
cat("PASS compatible historical R6 retained when adding glue\n")
unlink(project, recursive = TRUE)
