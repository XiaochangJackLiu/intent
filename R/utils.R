#' @keywords internal
`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}

#' Check whether a string looks like an HTTP(S) URL
#'
#' Returns `TRUE` when `x` starts with `http://` or `https://`.
#' Used to distinguish repository names from repository URLs in lockfile
#' records (old versions of renv wrote full URLs as the Repository field).
#'
#' @param x Character vector of length 1.
#' @return `TRUE` if `x` is an HTTP or HTTPS URL.
#' @keywords internal
is_http_url <- function(x) {
  grepl("^https?://", x)
}

#' Load default repositories
#'
#' Reads the `INTENT_DEFAULT_REPOS` environment variable.  When set, it should
#' contain comma-separated `NAME=URL` pairs.  When unset, the CRAN mirror at
#' <https://cran.r-project.org> is returned.  Set to an empty string to force
#' explicit repository declaration on every init.
#'
#' @return A named character vector of repository URLs.
#' @keywords internal
load_default_repos <- function() {
  raw <- Sys.getenv("INTENT_DEFAULT_REPOS", unset = NA_character_)
  if (is.na(raw)) {
    return(c(CRAN = "https://cran.r-project.org"))
  }
  if (!nzchar(trimws(raw))) {
    return(character())
  }
  parts <- strsplit(raw, "\\s*,\\s*")[[1]]
  parts <- parts[nzchar(parts)]
  if (length(parts) == 0) {
    return(character())
  }
  pairs <- strsplit(parts, "=")
  repos <- vapply(
    pairs,
    function(p) if (length(p) >= 2) p[[2]] else "",
    character(1)
  )
  names(repos) <- vapply(
    pairs,
    function(p) if (length(p) >= 2) p[[1]] else "",
    character(1)
  )
  repos[names(repos) != "" & repos != ""]
}

#' Extract bare package name from a package reference
#'
#' Strips `user/repo` path prefixes and `@version` suffixes to return the
#' bare package name.
#'
#' @param pkg Character string. A package reference (e.g., `"dplyr"`,
#'   `"user/repo"`, `"dplyr@1.0.0"`, or `"user/repo@0.1.0"`).
#' @return The bare package name.
#' @keywords internal
extract_pkg_name <- function(pkg) {
  pkg_name <- basename(pkg)
  pkg_name <- gsub("@.*$", "", pkg_name)
  pkg_name
}

#' @keywords internal
normalize_project_path <- function(project) {
  normalizePath(path.expand(project), winslash = "/", mustWork = FALSE)
}

#' @keywords internal
find_project_from <- function(path) {
  current <- normalize_project_path(path)
  repeat {
    if (file.exists(file.path(current, "DESCRIPTION"))) {
      return(current)
    }

    parent <- dirname(current)
    if (identical(parent, current)) {
      return(NULL)
    }
    current <- parent
  }
}

#' @keywords internal
resolve_project <- function(project = NULL) {
  if (!is.null(project)) {
    project <- normalize_project_path(project)
    if (!dir.exists(project)) {
      stop("Project path does not exist: ", project, call. = FALSE)
    }
    if (!file.exists(file.path(project, "DESCRIPTION"))) {
      stop(
        "No DESCRIPTION file found in project: ",
        project,
        ". Run `intent::init()` first.",
        call. = FALSE
      )
    }
    return(project)
  }

  project <- find_project_from(getwd())
  if (!is.null(project)) {
    return(project)
  }

  stop(
    "No intent project found. Run `intent::init()` or pass `project =`.",
    call. = FALSE
  )
}

#' Load Repositories from DESCRIPTION
#'
#' Reads the repositories defined in `Config/intent/repos/` and returns
#' them as a named character vector.
#' @param project Path to the project directory.
#' @param more_repos Optional character vector of additional repositories.
#' @return A named character vector of repositories.
#' @keywords internal
load_intent_repos <- function(project, more_repos = NULL) {
  path_to_desc <- file.path(project, "DESCRIPTION")
  repos <- character()
  if (file.exists(path_to_desc)) {
    repos <- get_repos(path_to_desc)
  }

  if (length(more_repos) > 0) {
    # Combine with existing repos, prioritizing more_repos
    repos <- c(more_repos, repos)
  }

  repos
}

#' @keywords internal
intent_install <- function(project, pkgs) {
  path_to_desc <- file.path(project, "DESCRIPTION")
  overrides_info <- list(overrides = character(), extra_repos = character())
  if (file.exists(path_to_desc)) {
    overrides_info <- get_intent_overrides(path_to_desc)
  }

  repos <- load_intent_repos(project, more_repos = overrides_info$extra_repos)
  intent_preflight_package_sources(project, pkgs, overrides_info, repos)

  # Apply overrides to pkgs
  resolved_pkgs <- vapply(
    pkgs,
    function(pkg) {
      if (pkg %in% names(overrides_info$overrides)) {
        overrides_info$overrides[[pkg]]$ref
      } else {
        pkg
      }
    },
    character(1)
  )

  backend_install(project, resolved_pkgs, repos)
}

intent_preflight_package_sources <- function(
  project,
  pkgs,
  overrides_info,
  repos
) {
  source_policy <- get_source_policy(file.path(project, "DESCRIPTION"))
  if (identical(source_policy$mode, "off")) {
    return(invisible(TRUE))
  }

  violations <- intent_source_violations_empty()
  for (pkg in pkgs) {
    pkg_name <- extract_pkg_name(pkg)
    override <- overrides_info$overrides[[pkg_name]]

    if (!is.null(override)) {
      violations <- rbind(
        violations,
        intent_check_requested_source(
          project,
          pkg_name,
          override,
          repos,
          source_policy
        )
      )
    } else {
      source_class <- intent_package_ref_source_class(pkg)
      if (!isTRUE(source_policy$allow[[source_class]])) {
        violations <- rbind(
          violations,
          intent_source_violation(
            pkg_name,
            source_class,
            NA_character_,
            sprintf("source class '%s' is not allowed", source_class)
          )
        )
      }
    }
  }

  if (nrow(violations) == 0) {
    return(invisible(TRUE))
  }

  message(format_source_policy_violations(violations))
  if (identical(source_policy$mode, "error")) {
    stop(
      "Source policy violation. Package installation was not started.",
      call. = FALSE
    )
  }

  invisible(TRUE)
}

intent_check_requested_source <- function(
  project,
  pkg,
  override,
  repos,
  source_policy
) {
  source_class <- override$source_class
  if (!isTRUE(source_policy$allow[[source_class]])) {
    return(intent_source_violation(
      pkg,
      source_class,
      NA_character_,
      sprintf("source class '%s' is not allowed", source_class)
    ))
  }

  if (!is.null(override$repo)) {
    repo_name <- paste0("override_", pkg)
    if (
      !repo_name %in% names(load_intent_repos(project)) ||
        !identical(
          normalize_repo_url(load_intent_repos(project)[[repo_name]]),
          normalize_repo_url(override$repo)
        )
    ) {
      return(intent_source_violation(
        pkg,
        "repository",
        repo_name,
        sprintf(
          "repository '%s' is not declared in Config/intent/repos",
          repo_name
        )
      ))
    }
  }

  intent_source_violations_empty()
}

intent_package_ref_source_class <- function(pkg) {
  if (is_http_url(pkg)) {
    return("url")
  }
  if (grepl("^github::", pkg)) {
    return("github")
  }
  if (grepl("^bioc::", pkg)) {
    return("bioc")
  }
  if (grepl("^local::", pkg)) {
    return("local")
  }
  if (grepl("^url::", pkg)) {
    return("url")
  }
  if (grepl("/", pkg, fixed = TRUE)) {
    return("github")
  }
  "repository"
}

#' @keywords internal
intent_snapshot <- function(project, force = TRUE) {
  repos <- load_intent_repos(project)
  lockfile <- file.path(project, "renv.lock")
  candidate <- tempfile("renv-policy-", tmpdir = project, fileext = ".lock")
  on.exit(unlink(candidate), add = TRUE)

  backend_snapshot(project, repos, force = force, lockfile = candidate)
  lock <- renv::lockfile_read(candidate)
  lock <- intent_supplement_repositories(lock, repos)
  lock$R$Repositories <- repos
  intent_enforce_source_policy(project, lock, repos)
  renv::lockfile_write(lock, file = candidate, project = project)
  file.copy(candidate, lockfile, overwrite = TRUE)
  invisible(lockfile)
}

#' @keywords internal
intent_restore <- function(project) {
  repos <- load_intent_repos(project)
  backend_restore(project, repos)
}

intent_enforce_source_policy <- function(
  project,
  lock,
  repos = load_intent_repos(project)
) {
  source_policy <- get_source_policy(file.path(project, "DESCRIPTION"))
  violations <- intent_check_source_policy(lock, repos, source_policy)

  if (nrow(violations) == 0 || identical(source_policy$mode, "off")) {
    return(invisible(violations))
  }

  message(format_source_policy_violations(violations))

  if (identical(source_policy$mode, "error")) {
    stop(
      "Source policy violation. The official renv.lock was not updated.",
      call. = FALSE
    )
  }

  invisible(violations)
}

format_source_policy_violations <- function(violations) {
  lines <- c(
    sprintf("Source policy violations: %d", nrow(violations)),
    sprintf("  - %s: %s", violations$package, violations$reason)
  )
  paste(lines, collapse = "\n")
}

#' @keywords internal
intent_set_project_dep <- function(project, package, type, version = "*") {
  desc::desc_set_dep(
    package = package,
    type = type,
    version = version,
    file = file.path(project, "DESCRIPTION"),
    normalize = TRUE
  )
}

#' @keywords internal
intent_del_project_dep <- function(project, package) {
  desc::desc_del_dep(
    package = package,
    file = file.path(project, "DESCRIPTION"),
    normalize = TRUE
  )
}

#' @keywords internal
intent_get_project_deps <- function(project) {
  desc::desc_get_deps(
    file = file.path(project, "DESCRIPTION")
  )
}

#' @keywords internal
intent_sync_project <- function(project) {
  intent_snapshot(project)
  repos <- load_intent_repos(project)
  backend_restore(project, repos)
}
