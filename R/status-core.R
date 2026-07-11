# Core domain functions for project status inspection.
# These are called by the command layer (cmd_status) and by the public R API.

new_intent_status <- function(
  project,
  manifest_packages,
  locked_packages,
  missing_from_lockfile,
  extra_in_lockfile,
  library_path,
  missing_from_library,
  source_policy = NULL,
  source_violations = intent_source_violations_empty(),
  r_version = NULL,
  r_constraint = NULL,
  lockfile_r_version = NULL
) {
  structure(
    list(
      project = project,
      manifest_packages = manifest_packages,
      locked_packages = locked_packages,
      missing_from_lockfile = missing_from_lockfile,
      extra_in_lockfile = extra_in_lockfile,
      library_path = library_path,
      missing_from_library = missing_from_library,
      source_policy = source_policy,
      source_violations = source_violations,
      r_version = r_version %||% as.character(getRversion()),
      r_constraint = r_constraint,
      lockfile_r_version = lockfile_r_version
    ),
    class = "intent_status"
  )
}

new_intent_plan <- function(
  project,
  command,
  actions,
  packages = character()
) {
  structure(
    list(
      project = project,
      command = command,
      actions = actions,
      packages = packages
    ),
    class = "intent_plan"
  )
}

new_intent_verification <- function(project, ok, issues, status) {
  structure(
    list(
      project = project,
      ok = ok,
      issues = issues,
      status = status
    ),
    class = "intent_verification"
  )
}

intent_verification_issues_empty <- function() {
  data.frame(
    check = character(),
    severity = character(),
    message = character(),
    stringsAsFactors = FALSE
  )
}

intent_verification_issue <- function(check, severity, message) {
  data.frame(
    check = check,
    severity = severity,
    message = message,
    stringsAsFactors = FALSE
  )
}

#' Read the R version constraint from DESCRIPTION
#'
#' Returns the version constraint string (e.g. `">= 4.5"`) recorded in
#' `Depends: R`, or `NULL` when no R constraint is declared.
#'
#' @param project Path to the project directory.
#' @return Character string or NULL.
#' @keywords internal
intent_r_constraint <- function(project) {
  deps <- desc::desc_get_deps(file = file.path(project, "DESCRIPTION"))
  r_deps <- deps[deps$package == "R" & deps$type == "Depends", , drop = FALSE]
  if (nrow(r_deps) == 0) {
    return(NULL)
  }
  constraint <- r_deps$version[[1]]
  if (is.na(constraint) || !nzchar(constraint)) {
    return(NULL)
  }
  constraint
}

intent_manifest_packages <- function(project) {
  desc_deps <- desc::desc_get_deps(file = file.path(project, "DESCRIPTION"))
  target_types <- c("Imports", "Suggests")
  packages <- desc_deps$package[desc_deps$type %in% target_types]
  sort(unique(packages[packages != "R"]))
}

intent_locked_packages <- function(project) {
  lock_path <- file.path(project, "renv.lock")
  if (!file.exists(lock_path)) {
    return(character())
  }

  lock <- backend_read_lockfile(project)
  sort(names(lock$Packages %||% list()))
}

intent_lock_dependency_closure <- function(lock, roots) {
  packages <- lock$Packages %||% list()
  roots <- intersect(unique(roots), names(packages))
  seen <- character()
  queue <- roots

  while (length(queue) > 0) {
    pkg <- queue[[1]]
    queue <- queue[-1]

    if (pkg %in% seen) {
      next
    }

    seen <- c(seen, pkg)
    deps <- intent_lock_package_dependencies(packages[[pkg]])
    deps <- intersect(deps, names(packages))
    queue <- unique(c(queue, setdiff(deps, seen)))
  }

  sort(seen)
}

#' Base R packages (cached after first lookup)
#'
#' Returns the set of packages shipped with R that should be excluded from
#' dependency-closure calculations.  Queried from `installed.packages()` at
#' first call and cached for the remainder of the session.
#'
#' @return Character vector of base R package names.
#' @keywords internal
intent_base_packages <- local({
  pkgs <- NULL
  function() {
    if (is.null(pkgs)) {
      pkgs <- rownames(utils::installed.packages(priority = "base"))
      pkgs <- unique(c("R", pkgs))
    }
    pkgs
  }
})

intent_lock_package_dependencies <- function(record) {
  fields <- c("Depends", "Imports", "LinkingTo")
  deps <- unlist(record[intersect(fields, names(record))], use.names = FALSE)
  deps <- gsub("\\s*\\(.*\\)$", "", deps)
  deps <- trimws(deps)
  deps <- deps[nzchar(deps)]
  sort(setdiff(unique(deps), intent_base_packages()))
}

intent_source_violations_empty <- function() {
  data.frame(
    package = character(),
    source = character(),
    repository = character(),
    reason = character(),
    stringsAsFactors = FALSE
  )
}

intent_lockfile_provenance <- function(lock) {
  packages <- lock$Packages %||% list()
  rows <- lapply(names(packages), function(pkg) {
    record <- packages[[pkg]]
    source <- intent_lock_record_source(record)
    data.frame(
      package = pkg,
      source = source,
      repository = record[["Repository"]] %||% NA_character_,
      repository_url = intent_lock_record_repository_url(record),
      stringsAsFactors = FALSE
    )
  })

  if (length(rows) == 0) {
    return(data.frame(
      package = character(),
      source = character(),
      repository = character(),
      repository_url = character(),
      stringsAsFactors = FALSE
    ))
  }

  do.call(rbind, rows)
}

intent_lock_record_source <- function(record) {
  source <- tolower(record[["Source"]] %||% "")

  if (identical(source, "repository") || !is.null(record[["Repository"]])) {
    return("repository")
  }
  if (source %in% c("github", "bioconductor", "bioc", "url", "local")) {
    return(if (identical(source, "bioconductor")) "bioc" else source)
  }
  if (grepl("github", source, fixed = TRUE)) {
    return("github")
  }
  if (grepl("bioconductor|bioc", source)) {
    return("bioc")
  }
  if (is_http_url(record[["RemoteUrl"]] %||% "")) {
    return("url")
  }
  if (!is.null(record[["RemoteType"]])) {
    remote_type <- tolower(record[["RemoteType"]])
    if (remote_type %in% c("github", "bioc", "url", "local")) {
      return(remote_type)
    }
  }

  "unknown"
}

intent_lock_record_repository_url <- function(record) {
  candidates <- c(
    record[["RemoteRepos"]],
    record[["RepositoryURL"]],
    record[["RepoURL"]]
  )
  candidates <- candidates[!is.na(candidates) & nzchar(candidates)]
  if (length(candidates) == 0) {
    return(NA_character_)
  }
  candidates[[1]]
}

intent_check_source_policy <- function(lock, repos, source_policy) {
  if (is.null(source_policy) || identical(source_policy$mode, "off")) {
    return(intent_source_violations_empty())
  }

  provenance <- intent_lockfile_provenance(lock)
  if (nrow(provenance) == 0) {
    return(intent_source_violations_empty())
  }

  provenance <- provenance[
    !provenance$package %in% source_policy$exempt_packages,
    ,
    drop = FALSE
  ]
  if (nrow(provenance) == 0) {
    return(intent_source_violations_empty())
  }

  violations <- intent_source_violations_empty()
  for (i in seq_len(nrow(provenance))) {
    row <- provenance[i, , drop = FALSE]
    source <- row$source
    if (!isTRUE(source_policy$allow[[source]])) {
      violations <- rbind(
        violations,
        intent_source_violation(
          row$package,
          source,
          row$repository,
          sprintf("source class '%s' is not allowed", source)
        )
      )
      next
    }

    if (identical(source, "repository")) {
      violations <- rbind(
        violations,
        intent_check_repository_policy(row, repos)
      )
    }
  }

  violations
}

intent_verify_project_issues <- function(project, status) {
  issues <- intent_verification_issues_empty()

  if (length(status$missing_from_lockfile) > 0) {
    issues <- rbind(
      issues,
      intent_verification_issue(
        "lockfile",
        "error",
        paste(
          "Packages declared in DESCRIPTION are missing from renv.lock:",
          paste(status$missing_from_lockfile, collapse = ", ")
        )
      )
    )
  }

  if (length(status$missing_from_library) > 0) {
    issues <- rbind(
      issues,
      intent_verification_issue(
        "library",
        "error",
        paste(
          "Packages recorded in renv.lock are missing from the project library:",
          paste(status$missing_from_library, collapse = ", ")
        )
      )
    )
  }

  lock_path <- file.path(project, "renv.lock")
  if (!file.exists(lock_path)) {
    issues <- rbind(
      issues,
      intent_verification_issue(
        "lockfile",
        "error",
        "renv.lock does not exist."
      )
    )
    return(issues)
  }

  lock <- backend_read_lockfile(project)
  repos <- load_intent_repos(project)

  # R version checks
  issues <- rbind(
    issues,
    intent_verify_r_version_issues(
      r_constraint = status$r_constraint,
      lockfile_r_version = status$lockfile_r_version
    )
  )

  issues <- rbind(issues, intent_verify_repository_issues(lock, repos))
  issues <- rbind(
    issues,
    intent_verify_source_policy_issues(status$source_violations)
  )
  issues <- rbind(
    issues,
    intent_check_platform_repos(repos, status$source_policy)
  )
  issues <- rbind(
    issues,
    intent_verify_lockfile_repo_resolvability(lock, repos)
  )
  issues <- rbind(
    issues,
    intent_verify_lockfile_closure_issues(
      lock,
      roots = c(status$manifest_packages, "intent", "pak", "renv")
    )
  )

  issues
}

intent_supplement_repositories <- function(lock, repos) {
  packages <- lock$Packages %||% list()
  repo_table <- lock$R$Repositories %||% character()
  supplemented <- FALSE
  undeclared <- character()

  for (pkg_record in packages) {
    repo_name <- pkg_record[["Repository"]]
    if (is.null(repo_name) || is.na(repo_name) || !nzchar(repo_name)) {
      next
    }
    # Skip URL-type Repository fields (old renv behaviour)
    if (is_http_url(repo_name)) {
      next
    }
    if (repo_name %in% names(repo_table)) {
      next
    }

    # Resolve via the package record's own URL fields
    record_url <- intent_lock_record_repository_url(pkg_record)
    if (!is.na(record_url) && nzchar(record_url)) {
      norm_record_url <- normalize_repo_url(record_url)
      for (decl_name in names(repos)) {
        if (
          identical(normalize_repo_url(repos[[decl_name]]), norm_record_url)
        ) {
          repo_table[[repo_name]] <- unname(repos[[decl_name]])
          supplemented <- TRUE
          break
        }
      }
      if (repo_name %in% names(repo_table)) {
        next
      }
    }

    # Collect undeclared names for messaging
    undeclared <- c(undeclared, repo_name)
  }

  if (length(undeclared) > 0) {
    undeclared <- unique(undeclared)
    known <- undeclared[undeclared %in% INTENT_KNOWN_PPM_NAMES]
    unknown <- setdiff(undeclared, known)

    if (length(known) > 0) {
      message(
        "Lockfile packages reference repository name(s) ",
        paste(sQuote(known), collapse = ", "),
        " which are not declared in Config/intent/repos. ",
        "These names are produced by the package repository server ",
        "(e.g. Posit Package Manager reports 'RSPM'). ",
        "Consider adding them to DESCRIPTION so renv::restore() can ",
        "resolve packages from this source."
      )
    }
    if (length(unknown) > 0) {
      message(
        "Lockfile packages reference undeclared repository name(s) ",
        paste(sQuote(unknown), collapse = ", "),
        ". These names are not declared in Config/intent/repos."
      )
    }
  }

  if (supplemented) {
    lock$R$Repositories <- repo_table
  }

  lock
}

intent_verify_r_version_issues <- function(
  r_constraint = NULL,
  lockfile_r_version = NULL
) {
  issues <- intent_verification_issues_empty()
  session_ver <- as.character(getRversion())

  # 1. Session compatibility: does current R satisfy the DESCRIPTION constraint?
  if (!is.null(r_constraint)) {
    parsed <- parse_r_version_constraint(r_constraint)
    if (!is.null(parsed) && !r_version_satisfies(session_ver, parsed)) {
      issues <- rbind(
        issues,
        intent_verification_issue(
          "r_version",
          "error",
          sprintf(
            "DESCRIPTION requires R %s, but the current session is R %s",
            r_constraint,
            session_ver
          )
        )
      )
    }
  }

  # 2. Lockfile consistency: does lockfile R satisfy the DESCRIPTION constraint?
  if (!is.null(lockfile_r_version) && !is.null(r_constraint)) {
    parsed <- parse_r_version_constraint(r_constraint)
    if (!is.null(parsed) && !r_version_satisfies(lockfile_r_version, parsed)) {
      issues <- rbind(
        issues,
        intent_verification_issue(
          "r_version",
          "error",
          sprintf(
            "DESCRIPTION requires R %s, but renv.lock records R %s",
            r_constraint,
            lockfile_r_version
          )
        )
      )
    }
  }

  # 3. Lockfile vs session: informational when they differ
  if (
    !is.null(lockfile_r_version) &&
      !identical(lockfile_r_version, session_ver)
  ) {
    issues <- rbind(
      issues,
      intent_verification_issue(
        "r_version",
        "info",
        sprintf(
          "renv.lock records R %s, current session is R %s",
          lockfile_r_version,
          session_ver
        )
      )
    )
  }

  issues
}

# Parse a constraint like ">= 4.5" into (op, major, minor)
parse_r_version_constraint <- function(constraint) {
  m <- regmatches(
    constraint,
    regexec("^(>=|>|==|<=|<)\\s*(\\d+)\\.(\\d+)", constraint)
  )[[1]]
  if (length(m) < 4) {
    return(NULL)
  }
  list(
    op = m[[2]],
    major = as.integer(m[[3]]),
    minor = as.integer(m[[4]])
  )
}

r_version_satisfies <- function(version, constraint) {
  parts <- as.integer(strsplit(version, "[.-]")[[1]])
  v_major <- parts[[1]]
  v_minor <- if (length(parts) >= 2) parts[[2]] else 0L

  switch(
    constraint$op,
    ">=" = v_major > constraint$major ||
      (v_major == constraint$major && v_minor >= constraint$minor),
    ">" = v_major > constraint$major ||
      (v_major == constraint$major && v_minor > constraint$minor),
    "==" = v_major == constraint$major && v_minor == constraint$minor,
    "<=" = v_major < constraint$major ||
      (v_major == constraint$major && v_minor <= constraint$minor),
    "<" = v_major < constraint$major ||
      (v_major == constraint$major && v_minor < constraint$minor),
    FALSE
  )
}

intent_verify_repository_issues <- function(lock, repos) {
  lock_repos <- intent_lock_repositories(lock)
  issues <- intent_verification_issues_empty()

  # --- "missing" check: repos in DESCRIPTION not in lockfile $R$Repositories ---
  missing <- setdiff(names(repos), names(lock_repos))
  if (length(missing) > 0) {
    # Filter: a repo is NOT truly missing if a lockfile repo has the same URL
    actually_missing <- character()
    for (name in missing) {
      decl_url <- normalize_repo_url(repos[[name]])
      url_found <- FALSE
      for (lock_url in lock_repos) {
        if (identical(normalize_repo_url(lock_url), decl_url)) {
          url_found <- TRUE
          break
        }
      }
      if (!url_found) {
        actually_missing <- c(actually_missing, name)
      }
    }
    if (length(actually_missing) > 0) {
      issues <- rbind(
        issues,
        intent_verification_issue(
          "repositories",
          "error",
          paste(
            "renv.lock is missing repositories declared in DESCRIPTION:",
            paste(actually_missing, collapse = ", ")
          )
        )
      )
    }
  }

  # --- "extra" check: repos in lockfile $R$Repositories not in DESCRIPTION ---
  extra <- setdiff(names(lock_repos), names(repos))
  if (length(extra) > 0) {
    # Filter: a repo is NOT truly extra if a declared repo has the same URL
    actually_extra <- character()
    for (name in extra) {
      lock_url <- normalize_repo_url(lock_repos[[name]])
      url_found <- FALSE
      for (decl_url in repos) {
        if (identical(normalize_repo_url(decl_url), lock_url)) {
          url_found <- TRUE
          break
        }
      }
      if (!url_found) {
        actually_extra <- c(actually_extra, name)
      }
    }
    if (length(actually_extra) > 0) {
      issues <- rbind(
        issues,
        intent_verification_issue(
          "repositories",
          "error",
          paste(
            "renv.lock contains repositories not declared in DESCRIPTION:",
            paste(actually_extra, collapse = ", ")
          )
        )
      )
    }
  }

  # --- URL mismatch check for same-named repos ---
  common <- intersect(names(repos), names(lock_repos))
  mismatched <- common[
    normalize_repo_url(repos[common]) != normalize_repo_url(lock_repos[common])
  ]
  if (length(mismatched) > 0) {
    issues <- rbind(
      issues,
      intent_verification_issue(
        "repositories",
        "error",
        paste(
          "renv.lock repository URLs differ from DESCRIPTION:",
          paste(mismatched, collapse = ", ")
        )
      )
    )
  }

  issues
}

intent_lock_repositories <- function(lock) {
  raw_repos <- lock$R$Repositories %||% character()
  if (length(raw_repos) == 0) {
    return(character())
  }

  repo_names <- names(raw_repos)
  repos <- unlist(raw_repos, use.names = FALSE)
  repos <- as.character(repos)
  names(repos) <- repo_names
  repos
}

intent_verify_source_policy_issues <- function(violations) {
  if (is.null(violations) || nrow(violations) == 0) {
    return(intent_verification_issues_empty())
  }

  do.call(
    rbind,
    lapply(seq_len(nrow(violations)), function(i) {
      violation <- violations[i, , drop = FALSE]
      intent_verification_issue(
        "source_policy",
        "error",
        sprintf("%s: %s", violation$package, violation$reason)
      )
    })
  )
}

intent_verify_lockfile_closure_issues <- function(lock, roots) {
  packages <- names(lock$Packages %||% list())
  retained <- intent_lock_dependency_closure(lock, roots = roots)
  zombies <- setdiff(packages, retained)

  if (length(zombies) == 0) {
    return(intent_verification_issues_empty())
  }

  intent_verification_issue(
    "lockfile_closure",
    "error",
    paste(
      "renv.lock contains packages not reachable from DESCRIPTION or bootstrap packages:",
      paste(zombies, collapse = ", ")
    )
  )
}

intent_verify_lockfile_repo_resolvability <- function(lock, repos) {
  packages <- lock$Packages %||% list()
  if (length(packages) == 0) {
    return(intent_verification_issues_empty())
  }

  issues <- intent_verification_issues_empty()
  repo_names <- names(repos)

  for (pkg_name in names(packages)) {
    record <- packages[[pkg_name]]
    repo <- record[["Repository"]]
    if (is.null(repo) || is.na(repo) || !nzchar(repo)) {
      next
    }

    # Direct name match — resolvable
    if (repo %in% repo_names) {
      next
    }

    # URL-match via package record's own URL fields
    record_url <- intent_lock_record_repository_url(record)
    if (!is.na(record_url) && nzchar(record_url)) {
      norm_record_url <- normalize_repo_url(record_url)
      url_matched <- FALSE
      for (decl_name in repo_names) {
        if (
          identical(normalize_repo_url(repos[[decl_name]]), norm_record_url)
        ) {
          url_matched <- TRUE
          break
        }
      }
      if (url_matched) {
        next
      }
    }

    # URL-match via lockfile R$Repositories entry for this repo name
    lock_repos <- lock$R$Repositories %||% character()
    if (repo %in% names(lock_repos)) {
      lock_repo_url <- lock_repos[[repo]]
      if (!is.na(lock_repo_url) && nzchar(lock_repo_url)) {
        norm_lock_url <- normalize_repo_url(lock_repo_url)
        url_matched <- FALSE
        for (decl_name in repo_names) {
          if (
            identical(normalize_repo_url(repos[[decl_name]]), norm_lock_url)
          ) {
            url_matched <- TRUE
            break
          }
        }
        if (url_matched) {
          next
        }
      }
    }

    # Unresolvable
    issues <- rbind(
      issues,
      intent_verification_issue(
        "lockfile_repo_resolvability",
        "error",
        sprintf(
          "Package '%s' references repository '%s' which is not declared in Config/intent/repos",
          pkg_name,
          repo
        )
      )
    )
  }

  issues
}

intent_source_violation <- function(package, source, repository, reason) {
  data.frame(
    package = package,
    source = source,
    repository = repository %||% NA_character_,
    reason = reason,
    stringsAsFactors = FALSE
  )
}

intent_check_repository_policy <- function(row, repos) {
  repository <- row$repository
  if (is.na(repository) || !nzchar(repository)) {
    return(intent_source_violation(
      row$package,
      row$source,
      repository,
      "repository source has no repository name"
    ))
  }

  repository_url <- row$repository_url

  # Case 1: Repository field IS a URL (old renv behaviour)
  if (is_http_url(repository)) {
    norm_repo <- normalize_repo_url(repository)
    for (decl_name in names(repos)) {
      if (identical(normalize_repo_url(repos[[decl_name]]), norm_repo)) {
        return(intent_source_violations_empty())
      }
    }
    return(intent_source_violation(
      row$package,
      row$source,
      repository,
      sprintf(
        "repository URL '%s' is not declared in Config/intent/repos",
        repository
      )
    ))
  }

  # Case 2: Direct name match
  if (repository %in% names(repos)) {
    if (
      !is.na(repository_url) &&
        nzchar(repository_url) &&
        !identical(
          normalize_repo_url(repository_url),
          normalize_repo_url(repos[[repository]])
        )
    ) {
      return(intent_source_violation(
        row$package,
        row$source,
        repository,
        sprintf(
          "repository '%s' URL does not match Config/intent/repos",
          repository
        )
      ))
    }
    return(intent_source_violations_empty())
  }

  # Case 3: Undeclared name — resolve against declared URLs via the
  # package's own repository_url.  Covers PPM (RSPM) and any future
  # repository name that resolves to a declared URL.
  if (
    !is.na(repository_url) &&
      nzchar(repository_url)
  ) {
    norm_pkg_url <- normalize_repo_url(repository_url)
    for (decl_name in names(repos)) {
      if (identical(normalize_repo_url(repos[[decl_name]]), norm_pkg_url)) {
        return(intent_source_violations_empty())
      }
    }
    return(intent_source_violation(
      row$package,
      row$source,
      repository,
      sprintf(
        "repository '%s' URL does not match any declared repository in Config/intent/repos",
        repository
      )
    ))
  }

  # Case 4: Unrecognised name, no repository_url to verify
  intent_source_violation(
    row$package,
    row$source,
    repository,
    sprintf(
      "repository '%s' is not declared in Config/intent/repos",
      repository
    )
  )
}

normalize_repo_url <- function(url) {
  sub("/+$", "", trimws(url))
}

repo_url_is_platform_specific <- function(url) {
  grepl(
    "__(linux|macos|windows|mac)__|manylinux|/macos/|/windows/",
    url
  )
}

intent_check_platform_repos <- function(repos, source_policy) {
  if (is.null(source_policy) || identical(source_policy$mode, "off")) {
    return(intent_verification_issues_empty())
  }

  issues <- intent_verification_issues_empty()
  for (repo_name in names(repos)) {
    url <- repos[[repo_name]]
    if (repo_url_is_platform_specific(url)) {
      severity <- if (identical(source_policy$mode, "error")) {
        "error"
      } else {
        "warning"
      }
      issues <- rbind(
        issues,
        intent_verification_issue(
          "platform_repos",
          severity,
          paste0(
            sprintf(
              "Config/intent/repos/%s uses a platform-specific URL: %s. ",
              repo_name,
              url
            ),
            "Cross-platform restore will fail on other operating systems. ",
            "Use a platform-agnostic URL."
          )
        )
      )
    }
  }
  issues
}

# Repository names that renv lockfile package records may contain even
# when the user declared the same source under a different name.  Used
# only to generate informative messages — never for silent behaviour
# changes.  PPM's PACKAGES file reports Repository: RSPM regardless of
# how the user names the repository in Config/intent/repos.
INTENT_KNOWN_PPM_NAMES <- c("RSPM")

intent_library_packages <- function(project) {
  library_path <- backend_library(project)
  if (!dir.exists(library_path)) {
    return(character())
  }

  sort(basename(list.dirs(library_path, full.names = TRUE, recursive = FALSE)))
}
