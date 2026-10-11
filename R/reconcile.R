# Shared user-workflow planning and execution. Environment mechanics stay in adapters.
intent_sync_plan <- function(project, prune = TRUE) {
  specs <- intent_dependency_specs(project)
  repos <- load_intent_repos(project)
  if (!length(repos)) {
    stop("No repositories configured in DESCRIPTION.", call. = FALSE)
  }
  lock <- intent_read_valid_lock(project)
  r_issues <- intent_verify_r_version_issues(
    intent_r_constraint(project),
    lock$R$Version
  )
  if (any(r_issues$severity == "error")) {
    stop(
      paste(r_issues$message[r_issues$severity == "error"], collapse = "\n"),
      call. = FALSE
    )
  }
  if (!is.null(lock)) {
    intent_enforce_source_policy(project, lock, repos)
    repository_issues <- intent_verify_lockfile_repo_resolvability(lock, repos)
    if (nrow(repository_issues)) {
      stop(paste(repository_issues$message, collapse = "\n"), call. = FALSE)
    }
  }
  info <- get_intent_overrides(file.path(project, "DESCRIPTION"))
  info$overrides <- specs$overrides
  intent_preflight_package_sources(project, specs$packages, info, repos)
  required <- intent_lock_mismatches(
    specs,
    lock %||% list(Packages = list()),
    repos
  )
  closure <- intent_lock_dependency_closure(lock %||% list(), specs$packages)
  extras <- setdiff(names(lock$Packages), closure)
  actions <- character()
  if (length(required)) {
    actions <- c(
      actions,
      paste0("would_install: ", paste(required, collapse = ", "))
    )
  }
  if (prune && length(extras)) {
    actions <- c(
      actions,
      paste0("would_prune: ", paste(extras, collapse = ", "))
    )
  }
  rewrite <- is.null(lock) ||
    length(required) > 0L ||
    (prune && length(extras) > 0L)
  if (rewrite) {
    actions <- c(actions, "would_snapshot")
  }
  actions <- c(actions, "would_restore", "would_verify")
  plan <- new_intent_plan(
    project,
    "sync",
    actions,
    if (prune) union(required, extras) else required
  )
  # Execution data stays internal; the public plan remains stable and serializable.
  list(
    plan = plan,
    specs = specs,
    repos = repos,
    lock = lock,
    required = required,
    extras = extras,
    rewrite = rewrite,
    prune = prune
  )
}

intent_normalize_candidate <- function(project, lock, repos) {
  old_table <- intent_lock_repositories(lock)
  used <- unique(vapply(
    lock$Packages %||% list(),
    function(x) x$Repository %||% "",
    character(1)
  ))
  aliases <- old_table[intersect(setdiff(used, names(repos)), names(old_table))]
  aliases <- aliases[normalize_repo_url(aliases) %in% normalize_repo_url(repos)]
  lock$R$Repositories <- c(repos, aliases)
  lock <- intent_supplement_repositories(lock, repos)
  lock
}

intent_commit_lock <- function(project, candidate) {
  official <- file.path(project, "renv.lock")
  backup <- tempfile("intent-lock-backup-", tmpdir = project)
  existed <- file.exists(official)
  if (existed && !file.copy(official, backup)) {
    stop("Could not back up renv.lock.", call. = FALSE)
  }
  on.exit(unlink(backup), add = TRUE)
  if (!file.copy(candidate, official, overwrite = TRUE)) {
    if (existed) {
      file.copy(backup, official, overwrite = TRUE)
    }
    stop("Could not replace renv.lock.", call. = FALSE)
  }
  invisible(official)
}

intent_assert_library <- function(
  project,
  lock,
  library = backend_library(project)
) {
  drift <- intent_library_drift(project, lock, library = library)
  problems <- unique(c(drift$missing, drift$versions, drift$sources))
  if (length(problems)) {
    stop(
      "Project library does not match resolved state: ",
      paste(problems, collapse = ", "),
      ". Library changes may have occurred; the lockfile was not committed.",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

intent_execute_sync <- function(project, workflow) {
  if (!workflow$rewrite) {
    intent_restore_verified(
      project,
      workflow$lock,
      workflow$repos,
      workflow$prune
    )
    return(invisible(workflow$plan))
  }
  stage <- tempfile("intent-stage-", tmpdir = project)
  dir.create(stage)
  on.exit(unlink(stage, recursive = TRUE), add = TRUE)
  library <- file.path(stage, "library")
  dir.create(library)
  backend_stage_tools(project, library)
  if (!is.null(workflow$lock)) {
    seed <- workflow$lock
    discard <- workflow$required
    if (workflow$prune) {
      discard <- union(discard, workflow$extras)
    }
    keep <- setdiff(names(seed$Packages), discard)
    seed$Packages <- seed$Packages[keep]
    if (length(seed$Packages)) {
      seed_path <- file.path(stage, "seed.lock")
      backend_write_lockfile(seed, project, path = seed_path)
      intent_restore_verified(
        project,
        seed,
        workflow$repos,
        library = library,
        lockfile = seed_path,
        clean = FALSE
      )
    }
  }
  overrides <- get_intent_overrides(file.path(project, "DESCRIPTION"))
  resolve_repos <- load_intent_repos(
    project,
    more_repos = overrides$extra_repos
  )
  evidence <- NULL
  if (length(workflow$required) || is.null(workflow$lock)) {
    evidence <- backend_resolve(project, workflow$specs, resolve_repos, library)
  }
  roots <- workflow$specs$packages
  if (!workflow$prune) {
    roots <- union(roots, workflow$extras)
  }
  candidate <- file.path(stage, "candidate.lock")
  backend_snapshot(
    project,
    workflow$repos,
    force = TRUE,
    lockfile = candidate,
    library = library,
    packages = roots
  )
  lock <- backend_read_lockfile(project, lockfile = candidate)
  lock <- intent_apply_resolution_provenance(lock, evidence, workflow$repos)
  lock <- intent_preserve_locked_provenance(
    lock,
    workflow$lock,
    workflow$required
  )
  lock <- intent_normalize_candidate(project, lock, workflow$repos)
  intent_validate_candidate(project, lock, workflow$specs)
  backend_write_lockfile(lock, project, path = candidate)
  intent_restore_verified(
    project,
    lock,
    workflow$repos,
    workflow$prune,
    candidate
  )
  intent_commit_lock(project, candidate)
  invisible(workflow$plan)
}

intent_restore_verified <- function(
  project,
  lock,
  repos,
  clean,
  lockfile = file.path(project, "renv.lock"),
  library = backend_library(project)
) {
  backend_restore(
    project,
    repos,
    lockfile = lockfile,
    clean = clean,
    library = library
  )
  drift <- intent_library_drift(project, lock, library = library)
  if (length(drift$sources)) {
    backend_restore(
      project,
      repos,
      lockfile = lockfile,
      clean = clean,
      library = library,
      rebuild = drift$sources
    )
  }
  intent_assert_library(project, lock, library = library)
}

intent_apply_resolution_provenance <- function(lock, evidence, repos) {
  # A binary's embedded Repository name can describe its build server. Map it
  # only when the installed pak plan supplies one unambiguous declared URL.
  for (resolved in evidence) {
    pkg <- resolved$package
    record <- lock$Packages[[pkg]]
    if (
      is.null(record) ||
        !identical(record$Version, resolved$version) ||
        intent_lock_record_source(record) != "repository" ||
        !resolved$type %in% c("standard", "cran") ||
        !is.na(intent_record_repo_url(record, lock))
    ) {
      next
    }
    sources <- unlist(resolved$sources, use.names = FALSE)
    matches <- repos[vapply(
      repos,
      function(repo) {
        any(startsWith(sources, paste0(normalize_repo_url(repo), "/")))
      },
      logical(1)
    )]
    urls <- unique(unname(normalize_repo_url(matches)))
    if (length(urls) == 1L) lock$Packages[[pkg]]$RepositoryURL <- urls[[1]]
  }
  lock
}

intent_preserve_locked_provenance <- function(lock, previous, changed) {
  # A fresh snapshot cannot recover URL evidence absent from embedded package
  # metadata. Preserve verified seed provenance only for unchanged identities.
  for (pkg in setdiff(
    intersect(names(lock$Packages), names(previous$Packages)),
    changed
  )) {
    record <- lock$Packages[[pkg]]
    old <- previous$Packages[[pkg]]
    if (
      intent_lock_record_source(record) != "repository" ||
        !identical(record$Version, old$Version) ||
        !identical(record$Repository, old$Repository) ||
        !is.na(intent_record_repo_url(record, lock))
    ) {
      next
    }
    url <- intent_record_repo_url(old, previous)
    if (!is.na(url)) lock$Packages[[pkg]]$RepositoryURL <- url
  }
  lock
}

intent_reconcile <- function(project, dry_run = FALSE, prune = TRUE) {
  workflow <- intent_sync_plan(project, prune)
  if (dry_run) {
    return(workflow$plan)
  }
  tryCatch(intent_execute_sync(project, workflow), error = function(e) {
    stop(
      "Reconciliation failed: ",
      conditionMessage(e),
      "\nThe official lockfile was retained. DESCRIPTION may contain pending edits; ",
      "library changes may have occurred. Correct the declaration or backend ",
      "failure and rerun sync().",
      call. = FALSE
    )
  })
}
