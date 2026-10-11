cmd_init <- function(
  path = ".",
  repos = NULL,
  r_version = NULL,
  install_self = "hydrate",
  confirm_repos = interactive(),
  use_default_repo = TRUE
) {
  install_self <- match.arg(install_self, c("hydrate", "never"))
  bootstrap_sources <- .libPaths()
  project_dir <- normalizePath(path, mustWork = FALSE)
  classification <- classify_init_description(project_dir)
  renv_state <- init_renv_state(project_dir)

  stop_for_unsafe_init(classification, renv_state)
  if (identical(classification$type, "intent_manifest")) {
    intent_sync_plan(project_dir)
  }

  desc_path <- file.path(project_dir, "DESCRIPTION")

  if (classification$type == "missing_manifest") {
    if (!dir.exists(path)) {
      dir.create(project_dir, recursive = TRUE)
    }
    pkg_name <- gsub("[^[:alnum:].]", ".", basename(project_dir))
    if (grepl("^[0-9.]", pkg_name)) {
      pkg_name <- paste0("pkg.", pkg_name)
    }
    message("Creating DESCRIPTION file...")
    rproject <- desc::description$new("!new")
    rproject$set("Package", pkg_name)
  } else {
    rproject <- desc::description$new(desc_path)
  }

  bootstrap_plan <- bootstrap_dependency_plan(rproject)
  apply_bootstrap_dependencies(rproject, bootstrap_plan)

  current_repos <- get_repos(desc_path)
  has_repos <- length(current_repos) > 0

  if (has_repos && length(repos) > 0) {
    warning("Repositories already exist in DESCRIPTION. Skipping.")
    repos <- current_repos
  } else if (!has_repos && length(repos) > 0) {
    repo_names <- names(repos)
    if (is.null(repo_names) || any(repo_names == "")) {
      stop(
        "Repositories must be provided as a named vector (e.g., c(CRAN = 'url'))."
      )
    }

    for (i in seq_along(repos)) {
      rproject$set(
        sprintf("Config/intent/repos/%s", repo_names[[i]]),
        repos[[i]]
      )
    }
  } else if (has_repos && (is.null(repos) || length(repos) == 0)) {
    repos <- get_repos(desc_path)
  } else if (!has_repos && (is.null(repos) || length(repos) == 0)) {
    if (!isTRUE(use_default_repo)) {
      stop(
        "No repositories configured. Pass `repos =` or add ",
        "`Config/intent/repos/` fields to DESCRIPTION.",
        call. = FALSE
      )
    }
    repos <- confirm_default_repos(
      load_default_repos(),
      confirm_repos = confirm_repos
    )
    if (!length(repos)) {
      stop("No repositories configured. Pass repos explicitly.", call. = FALSE)
    }
    for (i in seq_along(repos)) {
      rproject$set(
        sprintf("Config/intent/repos/%s", names(repos)[[i]]),
        repos[[i]]
      )
    }
  }

  # R version constraint
  existing_r <- rproject$get_deps()
  has_r <- any(existing_r$package == "R" & existing_r$type == "Depends")
  if (
    !isFALSE(r_version) &&
      !identical(r_version, NA) &&
      !(is.null(r_version) && has_r)
  ) {
    if (is.null(r_version)) {
      ver <- getRversion()
      r_version <- paste(ver$major, ver$minor, sep = ".")
    }
    if (is.character(r_version) && nzchar(r_version)) {
      constraint <- if (grepl("^[0-9]", r_version)) {
        paste(">=", r_version)
      } else {
        r_version
      }
      rproject$set_dep("R", type = "Depends", version = constraint)
    }
  }

  for (repo_name in names(repos)) {
    if (repo_url_is_platform_specific(repos[[repo_name]])) {
      warning(
        "Config/intent/repos/",
        repo_name,
        " uses a platform-specific URL: ",
        repos[[repo_name]],
        "\n",
        "Cross-platform restore will fail on other operating systems. ",
        "Use a platform-agnostic URL.",
        call. = FALSE
      )
    }
  }

  rproject$write(desc_path)

  if (!isTRUE(renv_state$renv_dir) && !isTRUE(renv_state$lockfile)) {
    backend_init(project_dir, repos)
  }
  backend_set_explicit(project_dir)
  hydrated <- maybe_hydrate_intent(project_dir, bootstrap_sources, install_self)
  intent_set_tool_lifecycle(project_dir, isTRUE(hydrated))
  intent_sync_project(project_dir)

  renviron_path <- file.path(project_dir, ".Renviron")
  renviron_lines <- if (file.exists(renviron_path)) {
    readLines(renviron_path)
  } else {
    character()
  }

  if (!any(grepl("RENV_CONFIG_PAK_ENABLED", renviron_lines))) {
    write(
      "# intent modification: start",
      file = renviron_path,
      append = TRUE
    )
    write("RENV_CONFIG_PAK_ENABLED = TRUE", file = renviron_path, append = TRUE)
    write("# intent modification: end", file = renviron_path, append = TRUE)
  }

  message("intent project initialized successfully in ", project_dir)
  message("Please restart your R session for changes to take effect.")
  invisible(project_dir)
}

classify_init_description <- function(project) {
  desc_path <- file.path(project, "DESCRIPTION")
  if (!file.exists(desc_path)) {
    return(list(type = "missing_manifest", error = NULL))
  }

  desc_obj <- tryCatch(
    desc::description$new(desc_path),
    error = function(e) e
  )
  if (inherits(desc_obj, "error")) {
    return(list(type = "invalid_manifest", error = conditionMessage(desc_obj)))
  }

  repos <- get_repos(desc_path)
  repo_names <- names(repos)
  has_valid_repos <- length(repos) > 0 &&
    !is.null(repo_names) &&
    all(nzchar(repo_names)) &&
    all(nzchar(repos))

  if (has_valid_repos) {
    return(list(type = "intent_manifest", error = NULL))
  }

  list(type = "non_intent_manifest", error = NULL)
}

init_renv_state <- function(project) {
  list(
    renv_dir = dir.exists(file.path(project, "renv")),
    lockfile = file.exists(file.path(project, "renv.lock"))
  )
}

stop_for_unsafe_init <- function(classification, renv_state) {
  switch(
    classification$type,
    invalid_manifest = stop(
      "DESCRIPTION exists but could not be parsed: ",
      classification$error,
      call. = FALSE
    ),
    non_intent_manifest = stop(
      "DESCRIPTION exists but is not an intent manifest. ",
      "Add `Config/intent/repos/<NAME>` fields to declare project repositories. ",
      "After the manifest is compliant, run `intent::init()` again.",
      call. = FALSE
    ),
    missing_manifest = {
      if (isTRUE(renv_state$renv_dir) || isTRUE(renv_state$lockfile)) {
        stop(
          "No DESCRIPTION file found, but existing renv state is present. ",
          "`intent::init()` cannot safely infer project intent from renv state ",
          "alone. Create an intent-compliant DESCRIPTION first.",
          call. = FALSE
        )
      }
    },
    intent_manifest = NULL,
    stop(
      "Internal error: unknown init classification '",
      classification$type,
      "'.",
      call. = FALSE
    )
  )

  invisible(TRUE)
}

confirm_default_repos <- function(repos, confirm_repos) {
  message(
    "No repositories configured. Proposed default repository: ",
    paste(sprintf("%s=%s", names(repos), repos), collapse = ", ")
  )

  if (!isTRUE(confirm_repos)) {
    message(
      "Using default repository. Pass `repos = c(NAME = 'URL')` or edit ",
      "`Config/intent/repos/` in DESCRIPTION to declare project repositories."
    )
    return(repos)
  }

  answer <- readline("Use this repository? [Y/n]: ")
  if (tolower(trimws(answer)) %in% c("", "y", "yes")) {
    return(repos)
  }

  stop(
    "Repository configuration cancelled. Pass `repos =` to declare project ",
    "repositories explicitly.",
    call. = FALSE
  )
}

maybe_hydrate_intent <- function(project, sources, install_self) {
  if (!identical(install_self, "hydrate")) {
    return(invisible(FALSE))
  }

  result <- tryCatch(
    backend_hydrate(project, "intent", sources = sources),
    error = function(e) e
  )

  intent_path <- file.path(backend_library(project), "intent")
  if (dir.exists(intent_path)) {
    message("Hydrated intent into the project library.")
    return(invisible(TRUE))
  }

  message(
    "intent was not found in the current library paths and was not installed ",
    "into the project library. After restarting R inside this renv project, ",
    "install intent into the project library or use an external intent CLI."
  )

  if (inherits(result, "error")) {
    message("Hydration detail: ", conditionMessage(result))
  }

  invisible(FALSE)
}

cmd_add <- function(pkgs, dev = FALSE, project = NULL, dry_run = FALSE) {
  if (missing(pkgs) || length(pkgs) == 0) {
    stop("No packages specified.", call. = FALSE)
  }

  project <- resolve_project(project)
  desc_type <- if (dev) "Suggests" else "Imports"
  intent_validate_package_args(pkgs)
  intent_sync_plan(project)
  info <- get_intent_overrides(file.path(project, "DESCRIPTION"))
  intent_preflight_package_sources(
    project,
    pkgs,
    info,
    load_intent_repos(project)
  )

  if (dry_run) {
    return(new_intent_plan(
      project = project,
      command = "add",
      packages = pkgs,
      actions = c(
        paste0("would_install: ", paste(pkgs, collapse = ", ")),
        paste0("would_update_manifest: ", desc_type),
        "would_snapshot"
      )
    ))
  }

  message("Adding ", paste(pkgs, collapse = ", "), " to ", desc_type)

  added <- character()
  for (pkg in pkgs) {
    pkg_name <- extract_pkg_name(pkg)
    current <- intent_get_project_deps(project)
    existing <- current[current$package == pkg_name, , drop = FALSE]
    version <- if (nrow(existing)) existing$version[[1]] else "*"
    if (!nrow(existing)) {
      added <- c(added, pkg_name)
    }
    if (
      grepl("@", pkg, fixed = TRUE) &&
        intent_package_ref_source_class(pkg) == "repository"
    ) {
      version <- intent_package_request_constraint(pkg)
    }
    intent_set_project_dep(
      project,
      package = pkg_name,
      type = desc_type,
      version = version
    )
    if (
      intent_package_ref_source_class(pkg) != "repository" || !nrow(existing)
    ) {
      intent_set_requested_remote(project, pkg_name, pkg)
    }
  }
  intent_reconcile(project)
  for (pkg in added) {
    deps <- intent_get_project_deps(project)
    if (identical(deps$version[deps$package == pkg][[1]], "*")) {
      intent_set_project_dep(
        project,
        pkg,
        desc_type,
        intent_get_installed_version(project, pkg)
      )
    }
  }

  invisible(pkgs)
}

cmd_remove <- function(pkgs, project = NULL, dry_run = FALSE) {
  if (missing(pkgs) || length(pkgs) == 0) {
    stop("No packages specified.", call. = FALSE)
  }

  project <- resolve_project(project)
  intent_validate_package_args(pkgs)
  declared <- intent_get_project_deps(project)$package
  undeclared <- setdiff(pkgs, declared)
  if (length(undeclared)) {
    stop(
      "Not a declared dependency: ",
      paste(undeclared, collapse = ", "),
      call. = FALSE
    )
  }
  intent_sync_plan(project)

  if (dry_run) {
    return(new_intent_plan(
      project = project,
      command = "remove",
      packages = pkgs,
      actions = c(
        paste0("would_remove_from_manifest: ", paste(pkgs, collapse = ", ")),
        paste0("would_remove_from_library: ", paste(pkgs, collapse = ", ")),
        "would_snapshot",
        "would_restore"
      )
    ))
  }

  message("Removing ", paste(pkgs, collapse = ", "), " from DESCRIPTION")
  for (pkg in pkgs) {
    intent_del_project_dep(project, package = pkg)
  }

  intent_reconcile(project)

  invisible(pkgs)
}

cmd_sync <- function(project = NULL, dry_run = FALSE, prune = TRUE) {
  project <- resolve_project(project)
  plan <- intent_reconcile(project, dry_run = dry_run, prune = prune)
  if (dry_run) {
    return(plan)
  }
  message("Environment synchronized.")
  invisible(plan)
}
cmd_status <- function(project = NULL) {
  project <- resolve_project(project)

  manifest_packages <- intent_manifest_packages(project)
  locked_packages <- intent_locked_packages(project)
  library_path <- backend_library(project)
  library_packages <- intent_library_packages(project)
  repos <- load_intent_repos(project)
  source_policy <- get_source_policy(file.path(project, "DESCRIPTION"))
  source_violations <- intent_source_violations_empty()

  # R version info
  r_constraint <- if (file.exists(file.path(project, "DESCRIPTION"))) {
    intent_r_constraint(project)
  }
  lockfile_r_version <- NULL
  mismatches <- character()
  drift <- list(versions = character(), sources = character())
  if (file.exists(file.path(project, "renv.lock"))) {
    lock <- intent_read_valid_lock(project)
    mismatches <- intent_lock_mismatches(
      intent_dependency_specs(project),
      lock,
      repos
    )
    drift <- intent_library_drift(project, lock)
    source_violations <- intent_check_source_policy(
      lock,
      repos = repos,
      source_policy = source_policy
    )
    lockfile_r_version <- lock$R$Version %||% NULL
  }

  new_intent_status(
    project = project,
    manifest_packages = manifest_packages,
    locked_packages = locked_packages,
    missing_from_lockfile = setdiff(manifest_packages, locked_packages),
    extra_in_lockfile = setdiff(locked_packages, manifest_packages),
    library_path = library_path,
    missing_from_library = setdiff(locked_packages, library_packages),
    source_policy = source_policy,
    source_violations = source_violations,
    r_constraint = r_constraint,
    lockfile_r_version = lockfile_r_version,
    incompatible_with_manifest = mismatches,
    version_mismatches = drift$versions,
    source_mismatches = drift$sources
  )
}

cmd_verify <- function(project = NULL) {
  project <- resolve_project(project)
  current_status <- cmd_status(project = project)
  issues <- intent_verify_project_issues(project, current_status)

  new_intent_verification(
    project = project,
    ok = !any(issues$severity == "error"),
    issues = issues,
    status = current_status
  )
}

cmd_adopt <- function(
  path = ".",
  repos = NULL,
  strategy = c("manifest", "lockfile-assisted"),
  dry_run = TRUE,
  install_self = "hydrate",
  confirm = interactive()
) {
  strategy <- match.arg(strategy)
  install_self <- match.arg(install_self, c("hydrate", "never"))

  project_dir <- normalizePath(
    path.expand(path),
    winslash = "/",
    mustWork = FALSE
  )
  desc_path <- file.path(project_dir, "DESCRIPTION")

  adopt_validate_manifest(desc_path)

  rproject <- desc::description$new(desc_path)

  current_repos <- get_repos(desc_path)
  effective_repos <- adopt_resolve_repos(current_repos, repos)

  plan <- adopt_build_plan(
    project_dir = project_dir,
    rproject = rproject,
    strategy = strategy,
    effective_repos = effective_repos,
    confirm = confirm,
    install_self = install_self
  )

  if (dry_run) {
    return(plan)
  }

  adopt_apply_plan(plan, project_dir, rproject, effective_repos, install_self)

  invisible(plan)
}
