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
for (constraint in c(">= 1.0.0", "== 1.8.1", "<= 1.8.1")) {
  project <- tempfile("intent-real-")
  dir.create(project)
  writeLines(
    c(
      "Package: capability",
      "Version: 0.0.1",
      paste0("Imports: glue (", constraint, ")"),
      "Config/intent/repos/CRAN: https://cloud.r-project.org",
      "Config/intent/tools/intent: external"
    ),
    file.path(project, "DESCRIPTION")
  )
  cat(
    "
CONSTRAINT ",
    constraint,
    "
"
  )
  intent:::cmd_sync(project)
  before <- readBin(
    file.path(project, "renv.lock"),
    "raw",
    n = file.info(file.path(project, "renv.lock"))$size
  )
  lock <- intent:::backend_read_lockfile(project)
  stopifnot(intent:::intent_version_satisfies(
    lock$Packages$glue$Version,
    constraint
  ))
  unlink(intent:::backend_library(project), recursive = TRUE)
  intent:::cmd_sync(project)
  after <- readBin(
    file.path(project, "renv.lock"),
    "raw",
    n = file.info(file.path(project, "renv.lock"))$size
  )
  stopifnot(identical(before, after), intent:::cmd_verify(project)$ok)
  cat(
    "PASS ",
    constraint,
    " version ",
    lock$Packages$glue$Version,
    "
"
  )
  unlink(project, recursive = TRUE)
}
