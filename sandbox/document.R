lib <- normalizePath("sandbox/bootstrap-library", winslash = "/")
.libPaths(c(lib, .Library), include.site = FALSE)
Sys.setenv(RENV_CONFIG_AUTOLOADER_ENABLED = "FALSE")
roxygen2::roxygenise()
