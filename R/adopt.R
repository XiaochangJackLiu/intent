#' Adopt an Existing R Project as an intent Project
#'
#' Converts an existing R project into an intent-managed project by adding
#' intent-specific metadata, bootstrap tool dependencies, and environment
#' configuration. The default strategy (\code{"manifest"}) treats the
#' existing \code{DESCRIPTION} as the source of truth for direct
#' dependencies and does not infer new dependencies from \code{renv.lock}.
#'
#' By default, \code{adopt()} is non-mutating: it returns an
#' \code{adoption_plan} that describes what would change. Pass
#' \code{dry_run = FALSE} to apply the changes.
#'
#' @param path Character string. Path to the project directory. Defaults to
#'   the current working directory.
#' @param repos Character vector. Named repositories to write into
#'   \code{Config/intent/repos/<NAME>} fields in \code{DESCRIPTION}. When
#'   \code{NULL} (default), reads existing \code{Config/intent/repos/*}
#'   fields from \code{DESCRIPTION}. A named vector is required when no
#'   repository fields exist.
#' @param strategy Character string. \code{"manifest"} (default) treats the
#'   existing \code{DESCRIPTION} as the source of truth for direct
#'   dependencies. \code{"lockfile-assisted"} reads \code{renv.lock} for
#'   candidate discovery.
#' @param dry_run Logical. If \code{TRUE} (default), returns an
#'   \code{adoption_plan} without modifying any files.
#' @param install_self Character string. \code{"hydrate"} (default) copies
#'   \code{intent} into the project library. \code{"never"} leaves it as an
#'   external tool.
#' @param confirm Logical. If \code{TRUE} and \code{strategy == "lockfile-assisted"},
#'   prompt for candidate selection. Defaults to \code{interactive()}.
#'
#' @return An \code{adoption_plan} object (invisibly when
#'   \code{dry_run = FALSE}).
#' @export
adopt <- function(
  path = ".",
  repos = NULL,
  strategy = c("manifest", "lockfile-assisted"),
  dry_run = TRUE,
  install_self = "hydrate",
  confirm = interactive()
) {
  cmd_adopt(
    path = path,
    repos = repos,
    strategy = strategy,
    dry_run = dry_run,
    install_self = install_self,
    confirm = confirm
  )
}
