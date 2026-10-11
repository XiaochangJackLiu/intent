lib <- file.path(getwd(), "sandbox", "bootstrap-library")
dir.create(lib, recursive = TRUE, showWarnings = FALSE)
.libPaths(c(lib, .Library), include.site = FALSE)
packages <- c("desc", "renv", "pak", "testthat", "pkgload", "mockery", "withr", "roxygen2", "jsonlite", "callr")
missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) {
  install.packages(missing, lib = lib, repos = "https://cloud.r-project.org", type = "binary")
}
stopifnot(all(vapply(packages, requireNamespace, logical(1), quietly = TRUE)))
cat("Test dependencies available in", lib, "\n")
