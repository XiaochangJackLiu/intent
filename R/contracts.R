# Intent-owned dependency constraints and identity checks.
intent_version_satisfies <- function(version, constraint = "*") {
  if (is.null(constraint) || is.na(constraint) || constraint %in% c("", "*")) {
    return(TRUE)
  }
  parts <- regmatches(
    constraint,
    regexec(
      "^\\s*(>=|<=|==|>|<)\\s*([0-9][0-9A-Za-z.-]*)\\s*$",
      constraint
    )
  )[[1]]
  if (length(parts) != 3L) {
    stop("Unsupported version constraint: ", constraint, call. = FALSE)
  }
  if (is.null(version) || is.na(version) || !nzchar(version)) {
    return(FALSE)
  }
  cmp <- utils::compareVersion(version, parts[[3]])
  switch(
    parts[[2]],
    ">=" = cmp >= 0,
    "<=" = cmp <= 0,
    "==" = cmp == 0,
    ">" = cmp > 0,
    "<" = cmp < 0
  )
}

intent_tool_is_external <- function(project) {
  manifest <- desc::description$new(file.path(project, "DESCRIPTION"))
  identical(
    manifest$get_field("Config/intent/tools/intent", default = "managed"),
    "external"
  )
}

intent_set_tool_lifecycle <- function(project, managed) {
  manifest <- desc::description$new(file.path(project, "DESCRIPTION"))
  manifest$set(
    "Config/intent/tools/intent",
    if (isTRUE(managed)) "managed" else "external"
  )
  manifest$write(file.path(project, "DESCRIPTION"))
}

intent_dependency_specs <- function(project) {
  deps <- intent_get_project_deps(project)
  deps <- deps[
    deps$type %in% c("Imports", "Suggests") & deps$package != "R",
    ,
    drop = FALSE
  ]
  if (intent_tool_is_external(project)) {
    deps <- deps[deps$package != "intent", , drop = FALSE]
  }
  overrides <- get_intent_overrides(file.path(project, "DESCRIPTION"))$overrides
  for (remote in intent_requested_remotes(project)) {
    pkg <- sub("=.*$", "", remote)
    ref <- sub("^[^=]+=", "", remote)
    if (is.null(overrides[[pkg]])) {
      overrides[[pkg]] <- list(
        package = pkg,
        ref = ref,
        version = NULL,
        source_class = intent_package_ref_source_class(ref)
      )
    }
  }
  for (pkg in unique(deps$package)) {
    versions <- deps$version[deps$package == pkg]
    for (constraint in versions) {
      # Parse even when no lock exists; validate before backend mutation.
      intent_version_satisfies("0", constraint)
      override <- overrides[[pkg]]
      if (
        !is.null(override$version) &&
          !intent_version_satisfies(override$version, constraint)
      ) {
        stop(
          "Override for ",
          pkg,
          " (",
          override$version,
          ") conflicts with DESCRIPTION constraint ",
          constraint,
          ".",
          call. = FALSE
        )
      }
    }
  }
  list(
    deps = deps,
    overrides = overrides,
    packages = sort(unique(deps$package))
  )
}

intent_record_matches_override <- function(record, override, lock, repos) {
  if (is.null(override)) {
    return(TRUE)
  }
  if (
    !is.null(override$version) && !identical(record$Version, override$version)
  ) {
    return(FALSE)
  }
  source <- intent_lock_record_source(record)
  if (!identical(source, override$source_class)) {
    return(FALSE)
  }
  if (!is.null(override$repo)) {
    url <- intent_record_repo_url(record, lock)
    return(
      !is.na(url) &&
        identical(normalize_repo_url(url), normalize_repo_url(override$repo))
    )
  }
  if (identical(source, "github")) {
    requested <- sub("^github::", "", sub("@[^@]+$", "", override$ref))
    identity <- paste(
      record$RemoteUsername %||% "",
      record$RemoteRepo %||% "",
      sep = "/"
    )
    ref <- record$RemoteRef %||% record$RemoteSha %||% ""
    target <- if (grepl("@", override$ref, fixed = TRUE)) {
      sub("^.*@", "", override$ref)
    } else {
      NULL
    }
    return(
      identical(tolower(identity), tolower(requested)) &&
        (is.null(target) ||
          identical(ref, target) ||
          identical(record$RemoteSha, target))
    )
  }
  if (source %in% c("url", "local")) {
    requested <- sub(paste0("^", source, "::"), "", override$ref)
    if (!is.null(override$version)) {
      requested <- sub("@[^@]+$", "", requested)
    }
    actual <- record$RemoteUrl %||% record$RemotePath
    return(!is.null(actual) && identical(actual, requested))
  }
  TRUE
}

intent_lock_mismatches <- function(specs, lock, repos) {
  mismatches <- character()
  for (pkg in specs$packages) {
    record <- lock$Packages[[pkg]]
    constraints <- specs$deps$version[specs$deps$package == pkg]
    matches <- !is.null(record) &&
      all(vapply(
        constraints,
        function(x) {
          intent_version_satisfies(record$Version, x)
        },
        logical(1)
      ))
    if (
      !matches ||
        !intent_record_matches_override(
          record,
          specs$overrides[[pkg]],
          lock,
          repos
        )
    ) {
      mismatches <- c(mismatches, pkg)
    }
  }
  mismatches
}

intent_read_valid_lock <- function(project) {
  if (!file.exists(file.path(project, "renv.lock"))) {
    return(NULL)
  }
  lock <- tryCatch(backend_read_lockfile(project), error = function(e) {
    stop("Cannot read renv.lock: ", conditionMessage(e), call. = FALSE)
  })
  if (
    !is.list(lock$R) ||
      is.null(lock$R$Version) ||
      length(lock$R$Version) != 1L ||
      is.na(lock$R$Version) ||
      !nzchar(lock$R$Version)
  ) {
    stop("Invalid renv.lock R version record.", call. = FALSE)
  }
  packages <- lock$Packages %||% list()
  if (
    !is.list(packages) ||
      (length(packages) &&
        (is.null(names(packages)) || any(!nzchar(names(packages)))))
  ) {
    stop("Invalid renv.lock package records.", call. = FALSE)
  }
  for (pkg in names(packages)) {
    version <- packages[[pkg]]$Version
    if (
      is.null(version) ||
        length(version) != 1L ||
        is.na(version) ||
        !nzchar(version)
    ) {
      stop("Invalid renv.lock version for ", pkg, ".", call. = FALSE)
    }
    absent <- setdiff(
      intent_lock_package_dependencies(packages[[pkg]]),
      names(packages)
    )
    if (length(absent)) {
      stop(
        "Invalid renv.lock: missing dependencies of ",
        pkg,
        ": ",
        paste(absent, collapse = ", "),
        call. = FALSE
      )
    }
  }
  lock
}

intent_record_repo_url <- function(record, lock = list()) {
  repo <- record$Repository %||% NA_character_
  if (!is.na(repo) && is_http_url(repo)) {
    return(repo)
  }
  url <- intent_lock_record_repository_url(record)
  if (!is.na(url)) {
    return(url)
  }
  table <- intent_lock_repositories(lock)
  if (!is.na(repo) && repo %in% names(table)) {
    return(unname(table[[repo]]))
  }
  NA_character_
}

intent_validate_candidate <- function(
  project,
  lock,
  specs = intent_dependency_specs(project)
) {
  repos <- load_intent_repos(project)
  intent_enforce_source_policy(project, lock, repos)
  repository_issues <- intent_verify_lockfile_repo_resolvability(lock, repos)
  if (nrow(repository_issues)) {
    stop(paste(repository_issues$message, collapse = "\n"), call. = FALSE)
  }
  missing <- intent_lock_mismatches(specs, lock, repos)
  for (pkg in names(lock$Packages)) {
    missing <- union(
      missing,
      setdiff(
        intent_lock_package_dependencies(lock$Packages[[pkg]]),
        names(lock$Packages)
      )
    )
  }
  if (length(missing)) {
    stop(
      "Candidate lockfile does not satisfy DESCRIPTION: ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

intent_library_drift <- function(
  project,
  lock,
  library = backend_library(project)
) {
  records <- backend_read_library(project, library = library)
  missing <- setdiff(names(lock$Packages), names(records))
  versions <- character()
  sources <- character()
  for (pkg in intersect(names(lock$Packages), names(records))) {
    locked <- lock$Packages[[pkg]]
    installed <- records[[pkg]]
    if (!identical(locked$Version, installed$Version)) {
      versions <- c(versions, pkg)
    }
    source <- intent_lock_record_source(installed)
    if (source != intent_lock_record_source(locked)) {
      sources <- c(sources, pkg)
    } else if (source == "repository") {
      locked_url <- intent_record_repo_url(locked, lock)
      installed_url <- intent_record_repo_url(installed, lock)
      if (
        !is.na(locked_url) &&
          !is.na(installed_url) &&
          normalize_repo_url(locked_url) != normalize_repo_url(installed_url)
      ) {
        sources <- c(sources, pkg)
      }
    } else if (source == "github") {
      fields <- c("RemoteUsername", "RemoteRepo", "RemoteSubdir")
      same_repo <- all(vapply(
        fields,
        function(field) identical(installed[[field]], locked[[field]]),
        logical(1)
      ))
      installed_ref <- installed$RemoteSha %||% installed$RemoteRef
      locked_ref <- locked$RemoteSha %||% locked$RemoteRef
      if (
        !same_repo ||
          is.null(installed_ref) ||
          is.null(locked_ref) ||
          !identical(installed_ref, locked_ref)
      ) {
        sources <- c(sources, pkg)
      }
    } else if (source %in% c("url", "local")) {
      actual <- installed$RemoteUrl %||% installed$RemotePath
      expected <- locked$RemoteUrl %||% locked$RemotePath
      if (
        is.null(actual) || is.null(expected) || !identical(actual, expected)
      ) {
        sources <- c(sources, pkg)
      }
    }
  }
  list(missing = missing, versions = versions, sources = sources)
}

intent_validate_package_args <- function(pkgs) {
  if (!is.character(pkgs) || anyNA(pkgs) || any(!nzchar(trimws(pkgs)))) {
    stop("Package references must be non-empty strings.", call. = FALSE)
  }
  for (pkg in pkgs) {
    if (
      intent_package_ref_source_class(pkg) == "repository" &&
        grepl("@", pkg, fixed = TRUE)
    ) {
      intent_package_request_constraint(pkg)
    }
  }
}

intent_package_request_constraint <- function(pkg) {
  requested <- sub("^.*@", "", pkg)
  constraint <- if (grepl("^(>=|<=|==|>|<)", requested)) {
    requested
  } else {
    paste("==", requested)
  }
  intent_version_satisfies("0", constraint)
  constraint
}

intent_requested_remotes <- function(project) {
  manifest <- desc::description$new(file.path(project, "DESCRIPTION"))
  raw <- manifest$get_field("Remotes", default = "")
  refs <- trimws(unlist(strsplit(raw, ",", fixed = TRUE)))
  refs <- refs[nzchar(refs)]
  vapply(
    refs,
    function(ref) {
      if (grepl("^[A-Za-z][A-Za-z0-9.]*=", ref)) {
        ref
      } else {
        paste0(extract_pkg_name(ref), "=", ref)
      }
    },
    character(1)
  )
}

intent_set_requested_remote <- function(project, package, ref = NULL) {
  manifest <- desc::description$new(file.path(project, "DESCRIPTION"))
  refs <- intent_requested_remotes(project)
  refs <- refs[sub("=.*$", "", refs) != package]
  if (!is.null(ref) && intent_package_ref_source_class(ref) != "repository") {
    ref <- sub("^[A-Za-z][A-Za-z0-9.]*=", "", ref)
    refs <- c(refs, paste0(package, "=", ref))
  }
  if (length(refs)) {
    manifest$set("Remotes", paste(refs, collapse = ", "))
  } else {
    manifest$del("Remotes")
  }
  manifest$write(file.path(project, "DESCRIPTION"))
}
