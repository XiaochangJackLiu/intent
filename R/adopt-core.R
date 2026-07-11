# Adoption plan domain logic for intent::adopt().
# These are called by cmd_adopt() in R/commands.R.

new_adoption_plan <- function(
  project,
  strategy,
  actions,
  bootstrap,
  issues,
  candidates,
  ok
) {
  structure(
    list(
      project = project,
      strategy = strategy,
      actions = actions,
      bootstrap = bootstrap,
      issues = issues,
      candidates = candidates,
      ok = ok
    ),
    class = "adoption_plan"
  )
}

adoption_actions_empty <- function() {
  data.frame(
    action = character(),
    target = character(),
    detail = character(),
    stringsAsFactors = FALSE
  )
}

adoption_action <- function(action, target, detail) {
  data.frame(
    action = action,
    target = target,
    detail = detail,
    stringsAsFactors = FALSE
  )
}

adoption_issues_empty <- function() {
  data.frame(
    area = character(),
    severity = character(),
    message = character(),
    stringsAsFactors = FALSE
  )
}

adoption_issue <- function(area, severity, message) {
  data.frame(
    area = area,
    severity = severity,
    message = message,
    stringsAsFactors = FALSE
  )
}

adoption_candidates_empty <- function() {
  data.frame(
    package = character(),
    source = character(),
    reason = character(),
    stringsAsFactors = FALSE
  )
}

adoption_candidate <- function(package, source, reason) {
  data.frame(
    package = package,
    source = source,
    reason = reason,
    stringsAsFactors = FALSE
  )
}

adopt_validate_manifest <- function(desc_path) {
  if (!file.exists(desc_path)) {
    stop(
      "No DESCRIPTION file found. ",
      "`intent::adopt()` with strategy = \"manifest\" requires an existing ",
      "DESCRIPTION file. Create one first, or use `intent::init()` for a ",
      "new project.",
      call. = FALSE
    )
  }

  desc_obj <- tryCatch(
    desc::description$new(desc_path),
    error = function(e) e
  )
  if (inherits(desc_obj, "error")) {
    stop(
      "DESCRIPTION exists but could not be parsed: ",
      conditionMessage(desc_obj),
      call. = FALSE
    )
  }

  invisible(desc_path)
}

adopt_resolve_repos <- function(current_repos, repos_provided) {
  if (!is.null(repos_provided) && length(repos_provided) > 0) {
    repo_names <- names(repos_provided)
    if (is.null(repo_names) || any(repo_names == "")) {
      stop(
        "Repositories must be provided as a named vector ",
        "(e.g., c(CRAN = 'url')).",
        call. = FALSE
      )
    }
    return(repos_provided)
  }

  if (length(current_repos) > 0) {
    return(current_repos)
  }

  stop(
    "No repositories configured. Pass `repos =` with a named vector ",
    "(e.g., c(CRAN = 'https://cran.r-project.org')) or add ",
    "`Config/intent/repos/<NAME>` fields to DESCRIPTION.",
    call. = FALSE
  )
}

adopt_build_actions <- function(
  effective_repos,
  current_repos,
  bootstrap_plan,
  has_renviron_pak
) {
  actions <- adoption_actions_empty()

  # Repository actions
  for (repo_name in names(effective_repos)) {
    if (
      repo_name %in%
        names(current_repos) &&
        identical(effective_repos[[repo_name]], current_repos[[repo_name]])
    ) {
      actions <- rbind(
        actions,
        adoption_action(
          "preserve",
          sprintf("Config/intent/repos/%s", repo_name),
          effective_repos[[repo_name]]
        )
      )
    } else {
      actions <- rbind(
        actions,
        adoption_action(
          "add",
          sprintf("Config/intent/repos/%s", repo_name),
          effective_repos[[repo_name]]
        )
      )
    }
  }

  # Bootstrap dependency actions (from plan$add)
  if (nrow(bootstrap_plan$add) > 0) {
    for (i in seq_len(nrow(bootstrap_plan$add))) {
      pkg <- bootstrap_plan$add$package[[i]]
      ver <- bootstrap_plan$add$version[[i]]
      actions <- rbind(
        actions,
        adoption_action(
          "add",
          sprintf("Suggests: %s (%s)", pkg, ver),
          ""
        )
      )
    }
  }

  # Bootstrap dependency actions (from plan$preserve)
  if (nrow(bootstrap_plan$preserve) > 0) {
    for (i in seq_len(nrow(bootstrap_plan$preserve))) {
      pkg <- bootstrap_plan$preserve$package[[i]]
      ver <- bootstrap_plan$preserve$version[[i]]
      actions <- rbind(
        actions,
        adoption_action(
          "preserve",
          sprintf("Suggests: %s", pkg),
          ver
        )
      )
    }
  }

  # .Renviron action
  if (has_renviron_pak) {
    actions <- rbind(
      actions,
      adoption_action(
        "preserve",
        ".Renviron",
        "RENV_CONFIG_PAK_ENABLED already set"
      )
    )
  } else {
    actions <- rbind(
      actions,
      adoption_action(
        "add",
        ".Renviron",
        "RENV_CONFIG_PAK_ENABLED = TRUE"
      )
    )
  }

  actions
}

adopt_compare_lockfile <- function(project_dir) {
  desc_deps <- desc::desc_get_deps(file = file.path(project_dir, "DESCRIPTION"))
  target_types <- c("Imports", "Suggests")
  manifest_pkgs <- desc_deps$package[
    desc_deps$type %in% target_types & desc_deps$package != "R"
  ]
  manifest_pkgs <- sort(unique(manifest_pkgs))

  lock_path <- file.path(project_dir, "renv.lock")
  if (!file.exists(lock_path)) {
    return(list(
      manifest_pkgs = manifest_pkgs,
      locked_pkgs = character(),
      in_lockfile_not_manifest = character(),
      in_manifest_not_lockfile = manifest_pkgs
    ))
  }

  lock <- backend_read_lockfile(project_dir)
  locked_pkgs <- sort(names(lock$Packages %||% list()))

  list(
    manifest_pkgs = manifest_pkgs,
    locked_pkgs = locked_pkgs,
    in_lockfile_not_manifest = setdiff(locked_pkgs, manifest_pkgs),
    in_manifest_not_lockfile = setdiff(manifest_pkgs, locked_pkgs)
  )
}

adopt_check_renviron <- function(project_dir) {
  renviron_path <- file.path(project_dir, ".Renviron")
  if (!file.exists(renviron_path)) {
    return(FALSE)
  }
  any(grepl("RENV_CONFIG_PAK_ENABLED", readLines(renviron_path)))
}

adopt_build_issues <- function(bootstrap_plan, comparison, strategy, confirm) {
  issues <- adoption_issues_empty()

  # Bootstrap issues
  if (nrow(bootstrap_plan$issues) > 0) {
    for (i in seq_len(nrow(bootstrap_plan$issues))) {
      issues <- rbind(
        issues,
        adoption_issue(
          "bootstrap",
          bootstrap_plan$issues$severity[[i]],
          sprintf(
            "%s: %s",
            bootstrap_plan$issues$package[[i]],
            bootstrap_plan$issues$message[[i]]
          )
        )
      )
    }
  }

  # Manifest/lockfile drift
  if (length(comparison$in_manifest_not_lockfile) > 0) {
    issues <- rbind(
      issues,
      adoption_issue(
        "lockfile",
        "warning",
        paste(
          "Packages declared in DESCRIPTION but missing from renv.lock:",
          paste(comparison$in_manifest_not_lockfile, collapse = ", ")
        )
      )
    )
  }

  issues
}

adopt_build_candidates <- function(comparison, strategy, confirm) {
  candidates <- adoption_candidates_empty()

  if (length(comparison$in_lockfile_not_manifest) == 0) {
    return(candidates)
  }

  for (pkg in comparison$in_lockfile_not_manifest) {
    candidates <- rbind(
      candidates,
      adoption_candidate(
        pkg,
        "renv.lock",
        "present in lockfile but missing from DESCRIPTION"
      )
    )
  }

  candidates
}

adopt_build_plan <- function(
  project_dir,
  rproject,
  strategy,
  effective_repos,
  confirm
) {
  current_repos <- get_repos(file.path(project_dir, "DESCRIPTION"))

  bootstrap_plan <- bootstrap_dependency_plan(rproject, override = TRUE)

  comparison <- adopt_compare_lockfile(project_dir)

  has_renviron_pak <- adopt_check_renviron(project_dir)

  actions <- adopt_build_actions(
    effective_repos,
    current_repos,
    bootstrap_plan,
    has_renviron_pak
  )

  issues <- adopt_build_issues(bootstrap_plan, comparison, strategy, confirm)

  candidates <- adopt_build_candidates(comparison, strategy, confirm)

  ok <- bootstrap_plan$ok && !any(issues$severity == "error")

  new_adoption_plan(
    project = project_dir,
    strategy = strategy,
    actions = actions,
    bootstrap = bootstrap_plan,
    issues = issues,
    candidates = candidates,
    ok = ok
  )
}

adopt_apply_plan <- function(
  plan,
  project_dir,
  rproject,
  effective_repos,
  install_self
) {
  if (!isTRUE(plan$ok)) {
    stop(
      "Adoption plan has blocking issues:\n",
      paste(
        sprintf("- %s", plan$issues$message[plan$issues$severity == "error"]),
        collapse = "\n"
      ),
      call. = FALSE
    )
  }

  # Write repos to DESCRIPTION
  for (i in seq_along(effective_repos)) {
    rproject$set(
      sprintf("Config/intent/repos/%s", names(effective_repos)[[i]]),
      effective_repos[[i]]
    )
  }

  # Apply bootstrap dependencies
  apply_bootstrap_dependencies(rproject, plan$bootstrap)

  # Write DESCRIPTION
  rproject$write(file.path(project_dir, "DESCRIPTION"))

  # Write .Renviron if needed
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

  # Set renv snapshot type to explicit
  renv::settings$snapshot.type("explicit", project = project_dir)

  # Hydrate intent
  if (!identical(install_self, "never")) {
    bootstrap_sources <- .libPaths()
    maybe_hydrate_intent(project_dir, bootstrap_sources, install_self)
  }

  # Snapshot and restore
  intent_sync_project(project_dir)

  message("Project adopted successfully in ", project_dir)
  invisible(TRUE)
}
