backend_init <- function(project, repos) {
  renv::init(
    project = project,
    bare = TRUE,
    restart = FALSE,
    settings = list(
      snapshot.type = "explicit"
    ),
    repos = repos,
    load = FALSE
  )

  invisible(project)
}

backend_hydrate <- function(project, pkgs, sources = NULL) {
  renv::hydrate(
    packages = pkgs,
    library = backend_library(project),
    sources = sources,
    repos = character(),
    prompt = FALSE,
    report = FALSE,
    project = project
  )
}

backend_install <- function(project, pkgs, repos = NULL) {
  lib_loc <- backend_library(project)
  message("Installing packages into ", lib_loc, "...")
  if (length(repos) > 0) {
    old_repos <- options(repos = repos)
    on.exit(options(old_repos), add = TRUE)
  }
  pak::pkg_install(pkgs, lib = lib_loc, ask = FALSE)
}

backend_remove <- function(project, pkgs) {
  renv::remove(pkgs, project = project, library = backend_library(project))
}

backend_snapshot <- function(
  project,
  repos = NULL,
  force = FALSE,
  lockfile = file.path(project, "renv.lock"),
  library = backend_library(project),
  packages = NULL
) {
  sn_args <- list(
    project = project,
    library = library,
    lockfile = lockfile,
    dev = TRUE,
    prompt = FALSE,
    force = force,
    packages = packages
  )
  if (is.null(packages)) {
    sn_args$type <- "explicit"
  }
  if (length(repos) > 0) {
    sn_args$repos <- repos
  }
  do.call(renv::snapshot, sn_args)
}

backend_restore <- function(
  project,
  repos = NULL,
  library = backend_library(project),
  lockfile = file.path(project, "renv.lock"),
  clean = TRUE,
  rebuild = FALSE
) {
  old_options <- options(renv.config.pak.enabled = FALSE)
  on.exit(options(old_options), add = TRUE)
  if (isTRUE(rebuild) || (is.character(rebuild) && length(rebuild))) {
    cache_options <- options(
      renv.config.cache.enabled = FALSE,
      renv.config.install.shortcuts = FALSE
    )
    on.exit(options(cache_options), add = TRUE)
    if (is.character(rebuild)) {
      renv::remove(rebuild, project = project, library = library)
    }
  }
  if (file.exists(lockfile)) {
    state <- backend_read_lockfile(project, lockfile)
    for (pkg in names(state$Packages)) {
      record <- state$Packages[[pkg]]
      if (intent_lock_record_source(record) == "repository") {
        url <- intent_record_repo_url(record, state)
        if (!is.na(url)) state$Packages[[pkg]]$Repository <- url
      }
    }
    transport_lock <- tempfile(
      "intent-restore-",
      tmpdir = project,
      fileext = ".lock"
    )
    on.exit(unlink(transport_lock), add = TRUE)
    backend_write_lockfile(state, project, path = transport_lock)
    lockfile <- transport_lock
  }
  res_args <- list(
    project = project,
    library = library,
    lockfile = lockfile,
    clean = clean,
    transactional = TRUE,
    strict = TRUE,
    retry = FALSE,
    rebuild = rebuild,
    exclude = "intent",
    prompt = FALSE
  )
  if (length(repos) > 0) {
    res_args$repos <- repos
  }
  do.call(renv::restore, res_args)
}

backend_read_lockfile <- function(
  project,
  lockfile = file.path(project, "renv.lock")
) {
  renv::lockfile_read(lockfile)
}

backend_write_lockfile <- function(
  lockfile,
  project,
  path = file.path(project, "renv.lock")
) {
  renv::lockfile_write(
    lockfile,
    file = path,
    project = project
  )
}

backend_library <- function(project) {
  renv::paths$library(project = project)
}

backend_set_explicit <- function(project) {
  renv::settings$snapshot.type("explicit", project = project)
}

backend_read_library <- function(project, library = backend_library(project)) {
  records <- list()
  if (!dir.exists(library)) {
    return(records)
  }
  for (path in list.dirs(library, recursive = FALSE, full.names = TRUE)) {
    description <- file.path(path, "DESCRIPTION")
    if (!file.exists(description)) {
      next
    }
    record <- tryCatch(
      as.list(read.dcf(description)[1, ]),
      error = function(e) NULL
    )
    if (!is.null(record$Package) && !is.null(record$Version)) {
      records[[record$Package]] <- record
    }
  }
  records
}

backend_stage_tools <- function(project, library) {
  # Self hydration is source-neutral: only copy the explicitly selected library.
  source <- backend_library(project)
  for (pkg in intersect(
    c("intent", "pak", "renv"),
    names(backend_read_library(project))
  )) {
    if (!file.copy(file.path(source, pkg), library, recursive = TRUE)) {
      stop("Could not stage tool package ", pkg, ".", call. = FALSE)
    }
  }
}

backend_resolve <- function(project, specs, repos, library) {
  manifest_dir <- tempfile("intent-resolve-")
  dir.create(manifest_dir)
  on.exit(unlink(manifest_dir, recursive = TRUE), add = TRUE)
  manifest <- desc::description$new("!new")
  manifest$set("Package", "intent.resolution")
  manifest$del(c("Depends", "Imports", "Suggests", "LinkingTo", "Remotes"))
  deps <- specs$deps[specs$deps$package != "intent", , drop = FALSE]
  for (i in seq_len(nrow(deps))) {
    manifest$set_dep(
      deps$package[[i]],
      type = "Imports",
      version = deps$version[[i]]
    )
  }
  intent_desc <- file.path(library, "intent", "DESCRIPTION")
  if (file.exists(intent_desc) && "intent" %in% specs$packages) {
    tool_deps <- desc::desc_get_deps(file = intent_desc)
    tool_deps <- tool_deps[
      tool_deps$type %in%
        c("Depends", "Imports", "LinkingTo") &
        tool_deps$package != "R",
      ,
      drop = FALSE
    ]
    for (i in seq_len(nrow(tool_deps))) {
      if (!manifest$has_dep(tool_deps$package[[i]])) {
        manifest$set_dep(
          tool_deps$package[[i]],
          "Imports",
          tool_deps$version[[i]]
        )
      }
    }
  }
  remotes <- vapply(
    intersect(names(specs$overrides), deps$package),
    function(pkg) {
      override <- specs$overrides[[pkg]]
      if (override$source_class %in% c("repository", "bioc")) {
        override$ref
      } else {
        paste0(pkg, "=", override$ref)
      }
    },
    character(1)
  )
  # DESCRIPTION constraints constrain the current repository candidates; explicit
  # pak references also make an exact historical version available to the solver.
  for (pkg in setdiff(unique(deps$package), names(specs$overrides))) {
    constraints <- deps$version[deps$package == pkg]
    exact <- constraints[grepl("^\\s*==", constraints)]
    if (length(exact)) {
      version <- sub("^\\s*==\\s*", "", exact[[1]])
      remotes <- c(remotes, paste0(pkg, "@", version))
    }
  }
  if (length(remotes)) {
    manifest$set("Remotes", paste(remotes, collapse = ", "))
  }
  manifest$write(file.path(manifest_dir, "DESCRIPTION"))
  old <- options(repos = repos)
  on.exit(options(old), add = TRUE)
  resolution <- file.path(manifest_dir, "pak.lock")
  pak::lockfile_create(
    paste0("deps::", normalizePath(manifest_dir, winslash = "/")),
    lockfile = resolution,
    lib = library,
    upgrade = FALSE,
    dependencies = NA
  )
  pak::lockfile_install(resolution, lib = library, update = TRUE)
  jsonlite::read_json(resolution)$packages
}
