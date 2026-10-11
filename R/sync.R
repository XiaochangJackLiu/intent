#' Sync the Environment
#'
#' Resolves dependencies whose locked versions or sources no longer satisfy
#' `DESCRIPTION`, preferring compatible locked versions. Validates a staged
#' candidate, restores the project library, and commits the lock after success.
#' An already compatible lock is restored without rewriting it.
#' @param project Path to the project directory. Defaults to the current intent project.
#' @param dry_run Logical. If `TRUE`, returns the planned actions without changing files or packages.
#' @param prune Logical. If `TRUE` (default), removes packages from the lockfile
#'   outside the dependency closure of `DESCRIPTION`. If `FALSE`, retains extras.
#'
#' @export
sync <- function(project = NULL, dry_run = FALSE, prune = TRUE) {
  cmd_sync(project = project, dry_run = dry_run, prune = prune)
}
