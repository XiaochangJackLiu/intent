lib <- normalizePath("sandbox/bootstrap-library", winslash = "/")
.libPaths(c(lib, .Library), include.site = FALSE)
Sys.setenv(
  R_LIBS_USER = lib,
  R_LIBS_SITE = "",
  RENV_CONFIG_AUTOLOADER_ENABLED = "FALSE"
)
status <- system2(
  file.path(R.home("bin"), "R.exe"),
  c("CMD", "INSTALL", paste0("--library=", shQuote(lib)), "."),
  stdout = "",
  stderr = ""
)
quit(status = status)
