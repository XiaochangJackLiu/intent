#' Initialize an intent Project
#'
#' Sets up a directory as an `intent` project. `init()` first classifies the
#' existing `DESCRIPTION` file, if any, before mutating project files. Existing
#' projects must already have an intent-compliant `DESCRIPTION` with
#' `Config/intent/repos/` fields; otherwise init stops before rewriting
#' `renv.lock`, `.Rprofile`, `.Renviron`, or the project library.
#'
#' For new empty projects, `init()` creates `DESCRIPTION`, initializes a bare
#' `renv` environment, sets the snapshot type to "explicit", and configures
#' `.Rprofile` and `.Renviron`. The bootstrap dependency on `intent` is written
#' with a default lower-bound version constraint. Minimum `pak` and `renv`
#' constraints are copied from the running `intent` package metadata when
#' declared there; existing user constraints are preserved.
#'
#' @param path Character string. Path to the new project directory. Defaults to current working directory.
#' @param repos Character vector. Named repositories to use. Defaults to
#'   the value of the `INTENT_DEFAULT_REPOS` environment variable (format:
#'   `"NAME=URL,NAME=URL"`), or the CRAN mirror at
#'   <https://cran.r-project.org> when the variable is
#'   unset. Set the variable to an empty string to require explicit
#'   repository configuration on every init.
#' @param r_version R version constraint to write into `DESCRIPTION` as
#'   `Depends: R (>= x.y)`.  Use `NULL` (the default) to record the
#'   current session's major.minor version, or `NA` to skip writing an R
#'   version constraint.
#' @param install_self Character string. `"hydrate"` attempts to copy the
#'   currently installed `intent` package from the active library paths into the
#'   new project library. `"never"` leaves `intent` as an external tool only.
#' @param confirm_repos Logical. If `TRUE`, ask before writing the default
#'   repository when no repository is configured. Defaults to `interactive()`.
#'
#' @export
init <- function(
  path = ".",
  repos = NULL,
  r_version = NULL,
  install_self = "hydrate",
  confirm_repos = interactive()
) {
  cmd_init(
    path = path,
    repos = repos,
    r_version = r_version,
    install_self = install_self,
    confirm_repos = confirm_repos
  )
}
