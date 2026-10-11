contract_project <- function(imports = "glue (>= 1.0.0)", extra = character()) {
  project <- tempfile("intent-contract-")
  dir.create(project)
  writeLines(
    c(
      "Package: contract",
      "Version: 0.0.1",
      if (nzchar(imports)) paste("Imports:", imports),
      "Config/intent/repos/CRAN: https://example.com",
      "Config/intent/tools/intent: external",
      extra
    ),
    file.path(project, "DESCRIPTION")
  )
  project
}

contract_record <- function(version = "1.0.0", ...) {
  c(
    list(
      Package = "glue",
      Version = version,
      Source = "Repository",
      Repository = "CRAN"
    ),
    list(...)
  )
}

contract_lock <- function(project, packages = list(glue = contract_record())) {
  lock <- list(
    R = list(
      Version = as.character(getRversion()),
      Repositories = c(CRAN = "https://example.com")
    ),
    Packages = packages
  )
  backend_write_lockfile(lock, project)
  lock
}
