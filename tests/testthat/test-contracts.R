test_that("full version constraints enforce lower, exact, upper and patch comparisons", {
  expect_true(intent_version_satisfies("1.2.3", ">= 1.2.3"))
  expect_false(intent_version_satisfies("1.2.2", ">= 1.2.3"))
  expect_true(intent_version_satisfies("1.2.3", "== 1.2.3"))
  expect_false(intent_version_satisfies("1.2.4", "<= 1.2.3"))
  expect_false(r_version_satisfies(
    "4.5.1",
    parse_r_version_constraint(">= 4.5.2")
  ))
  expect_error(intent_version_satisfies("1", "~ 1"), "Unsupported")
})

test_that("lock planning resolves only incompatible declarations and preserves compatible edits", {
  project <- contract_project()
  on.exit(unlink(project, recursive = TRUE))
  contract_lock(project)
  expect_false(intent_sync_plan(project)$rewrite)
  for (constraint in c(">= 1.1.0", "== 1.1.0", "< 1.0.0")) {
    intent_set_project_dep(project, "glue", "Imports", constraint)
    plan <- intent_sync_plan(project)
    expect_equal(plan$required, "glue")
    expect_true(plan$rewrite)
  }
  intent_set_project_dep(project, "glue", "Imports", "<= 1.1.0")
  expect_false(intent_sync_plan(project)$rewrite)
})

test_that("missing and corrupt locks are distinguished without mutation", {
  project <- contract_project()
  on.exit(unlink(project, recursive = TRUE))
  expect_equal(intent_sync_plan(project)$required, "glue")
  expect_false(file.exists(file.path(project, "renv.lock")))
  writeLines("invalid JSON", file.path(project, "renv.lock"))
  expect_error(intent_sync_plan(project), "Cannot read")
  expect_equal(readLines(file.path(project, "renv.lock")), "invalid JSON")
})

test_that("same-version source changes trigger resolution and conflicting overrides fail", {
  project <- contract_project(extra = "Remotes: glue=github::owner/glue@v1")
  on.exit(unlink(project, recursive = TRUE))
  contract_lock(project)
  expect_equal(intent_sync_plan(project)$required, "glue")
  manifest <- desc::description$new(file.path(project, "DESCRIPTION"))
  manifest$set("Config/intent/Imports/glue", "glue@0.1.0@cran")
  manifest$write()
  expect_error(intent_sync_plan(project), "conflicts")
})

test_that("forbidden existing lock sources fail even without installation work", {
  project <- contract_project(
    extra = c(
      "Config/intent/source-policy/mode: error",
      "Config/intent/source-policy/allow/github: false"
    )
  )
  on.exit(unlink(project, recursive = TRUE))
  contract_lock(
    project,
    list(glue = list(Version = "1.0.0", Source = "GitHub"))
  )
  expect_error(intent_sync_plan(project), "Source policy violation")
})

test_that("prune plans retain transitive closure and no-prune retains extras", {
  project <- contract_project()
  on.exit(unlink(project, recursive = TRUE))
  contract_lock(
    project,
    list(
      glue = contract_record(Imports = list("child (>= 1)")),
      child = contract_record(),
      orphan = contract_record()
    )
  )
  workflow <- intent_sync_plan(project)
  expect_equal(workflow$extras, "orphan")
  expect_true(any(grepl("would_prune: orphan", workflow$plan$actions)))
  expect_false(intent_sync_plan(project, prune = FALSE)$rewrite)
  intent_set_project_dep(project, "newpkg", "Imports")
  workflow <- intent_sync_plan(project, prune = FALSE)
  expect_equal(workflow$required, "newpkg")
  expect_equal(workflow$extras, "orphan")
})

test_that("unchanged lock restoration never snapshots or resolves, including library drift", {
  project <- contract_project()
  on.exit(unlink(project, recursive = TRUE))
  lock <- contract_lock(project)
  before <- readLines(file.path(project, "renv.lock"))
  seen <- NULL
  local_mocked_bindings(
    backend_restore = function(project, repos, clean, ...) {
      seen <<- list(project, clean)
    },
    backend_snapshot = function(...) stop("unexpected snapshot"),
    backend_resolve = function(...) stop("unexpected resolution"),
    intent_assert_library = function(project, lock) TRUE
  )
  cmd_sync(project)
  expect_equal(seen[[1]], normalize_project_path(project))
  expect_true(seen[[2]])
  expect_equal(readLines(file.path(project, "renv.lock")), before)
})

test_that("invalid candidate and failed target restore preserve official lock", {
  for (failure in c("candidate", "restore")) {
    project <- contract_project("glue (>= 2.0.0)")
    contract_lock(project)
    before <- readLines(file.path(project, "renv.lock"))
    candidate <- list(
      R = list(
        Version = as.character(getRversion()),
        Repositories = c(CRAN = "https://example.com")
      ),
      Packages = list(
        glue = contract_record(if (failure == "candidate") "1.0.0" else "2.0.0")
      )
    )
    restored <- FALSE
    local_mocked_bindings(
      backend_stage_tools = function(...) NULL,
      backend_resolve = function(...) NULL,
      backend_snapshot = function(
        project,
        repos,
        force,
        lockfile,
        library,
        packages
      ) {
        backend_write_lockfile(candidate, project, path = lockfile)
      },
      backend_restore = function(...) {
        restored <<- TRUE
        stop("target restore failed")
      }
    )
    expect_error(
      cmd_sync(project),
      if (failure == "candidate") {
        "does not satisfy"
      } else {
        "target restore failed"
      }
    )
    expect_identical(restored, failure == "restore")
    expect_equal(readLines(file.path(project, "renv.lock")), before)
    expect_false(any(grepl("^intent-stage-", list.files(project))))
    unlink(project, recursive = TRUE)
  }
})

test_that("successful staged resolution commits only after verified restoration", {
  project <- contract_project("glue (>= 2.0.0)")
  on.exit(unlink(project, recursive = TRUE))
  contract_lock(project)
  events <- character()
  candidate <- list(
    R = list(
      Version = as.character(getRversion()),
      Repositories = c(CRAN = "https://example.com")
    ),
    Packages = list(glue = contract_record("2.0.0"))
  )
  local_mocked_bindings(
    backend_stage_tools = function(...) NULL,
    backend_resolve = function(...) {
      events <<- c(events, "resolve")
      NULL
    },
    backend_snapshot = function(
      project,
      repos,
      force,
      lockfile,
      library,
      packages
    ) {
      events <<- c(events, "snapshot")
      backend_write_lockfile(candidate, project, path = lockfile)
    },
    backend_restore = function(...) events <<- c(events, "restore"),
    intent_assert_library = function(project, lock) {
      expect_equal(
        backend_read_lockfile(project)$Packages$glue$Version,
        "1.0.0"
      )
      events <<- c(events, "verify")
    }
  )
  cmd_sync(project)
  expect_equal(events, c("resolve", "snapshot", "restore", "verify"))
  expect_equal(backend_read_lockfile(project)$Packages$glue$Version, "2.0.0")
})

test_that("status detects installed version, source and missing provenance drift", {
  project <- contract_project()
  on.exit(unlink(project, recursive = TRUE))
  lock <- contract_lock(project)
  local_mocked_bindings(backend_read_library = function(...) {
    list(glue = contract_record("0.9.0"))
  })
  expect_equal(cmd_status(project)$version_mismatches, "glue")
  local_mocked_bindings(backend_read_library = function(...) {
    list(glue = list(Version = "1.0.0", Source = "GitHub"))
  })
  expect_equal(cmd_status(project)$source_mismatches, "glue")
  local_mocked_bindings(backend_read_library = function(...) {
    list(glue = list(Version = "1.0.0"))
  })
  expect_equal(intent_library_drift(project, lock)$sources, "glue")
})

test_that("external intent is excluded and remove clears source declarations", {
  project <- contract_project(
    "intent, glue",
    extra = "Remotes: glue=github::owner/glue"
  )
  on.exit(unlink(project, recursive = TRUE))
  expect_equal(intent_dependency_specs(project)$packages, "glue")
  intent_del_project_dep(project, "glue")
  expect_length(intent_requested_remotes(project), 0)
  expect_length(intent_dependency_specs(project)$packages, 0)
})

test_that("repository aliases and old URL records receive consistent verdicts", {
  repos <- c(CRAN = "https://example.com")
  for (repo in c("https://example.com/", "alias")) {
    lock <- list(
      R = list(Repositories = c(alias = "https://example.com")),
      Packages = list(
        glue = list(Version = "1", Source = "Repository", Repository = repo)
      )
    )
    expect_equal(
      nrow(intent_check_source_policy(
        lock,
        repos,
        intent_default_source_policy()
      )),
      0
    )
    expect_equal(
      nrow(intent_verify_lockfile_repo_resolvability(lock, repos)),
      0
    )
  }
  lock$R$Repositories <- c(alias = "https://untrusted.example")
  expect_equal(
    nrow(intent_check_source_policy(
      lock,
      repos,
      intent_default_source_policy()
    )),
    1
  )
  expect_equal(nrow(intent_verify_lockfile_repo_resolvability(lock, repos)), 1)
})

test_that("warnings and information do not fail verify", {
  project <- contract_project()
  on.exit(unlink(project, recursive = TRUE))
  local_mocked_bindings(
    cmd_status = function(...) NULL,
    intent_verify_project_issues = function(...) {
      rbind(
        intent_verification_issue("R", "info", "different patch"),
        intent_verification_issue("closure", "warning", "retained extra")
      )
    }
  )
  expect_true(cmd_verify(project)$ok)
  local_mocked_bindings(intent_verify_project_issues = function(...) {
    intent_verification_issue("R", "error", "incompatible")
  })
  expect_false(cmd_verify(project)$ok)
})

test_that("adoption lists backend effects and preserves constraints", {
  project <- contract_project("glue", extra = "Suggests: renv (< 1.0.0)")
  on.exit(unlink(project, recursive = TRUE))
  plan <- cmd_adopt(project, install_self = "never")
  expect_equal(
    plan$bootstrap$preserve$version[plan$bootstrap$preserve$package == "renv"],
    "< 1.0.0"
  )
  expect_true(all(
    c("configure", "external", "reconcile") %in% plan$actions$action
  ))
  output <- capture.output(print(plan))
  expect_true(any(grepl("reconcile", output)))
  expect_false(file.exists(file.path(project, "renv.lock")))
})

test_that("Remotes source policy is checked before resolution", {
  project <- contract_project(
    extra = c(
      "Remotes: glue=github::owner/glue",
      "Config/intent/source-policy/mode: error",
      "Config/intent/source-policy/allow/github: false"
    )
  )
  on.exit(unlink(project, recursive = TRUE))
  expect_error(cmd_sync(project, dry_run = TRUE), "Source policy violation")
  expect_false(file.exists(file.path(project, "renv.lock")))
})

test_that("structurally invalid locks and missing transitive records fail before mutation", {
  project <- contract_project()
  on.exit(unlink(project, recursive = TRUE))
  writeLines("{}", file.path(project, "renv.lock"))
  expect_error(intent_sync_plan(project), "Invalid renv.lock")
  contract_lock(
    project,
    list(glue = contract_record(Imports = "missing (>= 1)"))
  )
  expect_error(intent_sync_plan(project), "missing dependencies")
})

test_that("no-prune stages extras and compatible transitive versions when adding", {
  project <- contract_project("glue, newpkg")
  on.exit(unlink(project, recursive = TRUE))
  old <- contract_lock(
    project,
    list(
      glue = contract_record(Imports = "child"),
      child = contract_record("0.8.0"),
      orphan = contract_record("0.9.0")
    )
  )
  seed <- NULL
  roots <- NULL
  candidate <- old
  candidate$Packages$newpkg <- contract_record("2.0.0")
  local_mocked_bindings(
    backend_stage_tools = function(...) NULL,
    backend_resolve = function(...) NULL,
    backend_snapshot = function(
      project,
      repos,
      force,
      lockfile,
      library,
      packages
    ) {
      roots <<- packages
      backend_write_lockfile(candidate, project, path = lockfile)
    },
    backend_restore = function(
      project,
      repos,
      library = NULL,
      lockfile,
      clean
    ) {
      expect_false(clean)
      if (!is.null(library)) seed <<- backend_read_lockfile(project, lockfile)
    },
    intent_assert_library = function(...) TRUE
  )
  cmd_sync(project, prune = FALSE)
  expect_setequal(roots, c("glue", "newpkg", "orphan"))
  expect_equal(seed$Packages$child$Version, "0.8.0")
  expect_equal(seed$Packages$orphan$Version, "0.9.0")
  expect_equal(backend_read_lockfile(project)$Packages$orphan$Version, "0.9.0")
})

test_that("remove keeps a dependency still required transitively and clears its override", {
  project <- contract_project(
    "glue, child",
    extra = "Config/intent/Imports/child: child@1.0.0@cran"
  )
  on.exit(unlink(project, recursive = TRUE))
  contract_lock(
    project,
    list(glue = contract_record(Imports = "child"), child = contract_record())
  )
  local_mocked_bindings(
    backend_restore = function(...) NULL,
    intent_assert_library = function(...) TRUE
  )
  cmd_remove("child", project = project)
  expect_false("child" %in% intent_dependency_specs(project)$packages)
  expect_true("child" %in% names(backend_read_lockfile(project)$Packages))
  expect_null(intent_dependency_specs(project)$overrides$child)
  expect_error(cmd_remove("undeclared", project = project), "Not a declared")
})

test_that("R incompatibility fails before backend mutation", {
  project <- contract_project(extra = "Depends: R (>= 99.0.0)")
  on.exit(unlink(project, recursive = TRUE))
  local_mocked_bindings(backend_resolve = function(...) {
    stop("unexpected resolution")
  })
  expect_error(cmd_sync(project), "DESCRIPTION requires R")
})

test_that("resolver evidence maps build-server aliases only with a matching version and declared URL", {
  lock <- list(
    Packages = list(
      glue = list(Version = "1.8.1", Source = "Repository", Repository = "RSPM")
    )
  )
  repos <- c(CRAN = "https://cloud.r-project.org")
  evidence <- list(list(
    package = "glue",
    version = "1.8.1",
    type = "standard",
    sources = list(
      "https://cloud.r-project.org/bin/windows/contrib/4.5/glue_1.8.1.zip"
    )
  ))
  mapped <- intent_apply_resolution_provenance(lock, evidence, repos)
  expect_equal(mapped$Packages$glue$RepositoryURL, unname(repos))
  normalized <- intent_normalize_candidate(".", mapped, repos)
  expect_equal(normalized$R$Repositories[["RSPM"]], unname(repos))
  expect_equal(
    nrow(intent_verify_lockfile_repo_resolvability(normalized, repos)),
    0
  )
  evidence[[1]]$version <- "1.8.0"
  expect_null(
    intent_apply_resolution_provenance(
      lock,
      evidence,
      repos
    )$Packages$glue$RepositoryURL
  )
  evidence[[1]]$version <- "1.8.1"
  evidence[[1]]$sources <- list("https://untrusted.example/glue.zip")
  expect_null(
    intent_apply_resolution_provenance(
      lock,
      evidence,
      repos
    )$Packages$glue$RepositoryURL
  )
})

test_that("invalid add references and corrupt locks leave the manifest unchanged", {
  project <- contract_project()
  on.exit(unlink(project, recursive = TRUE))
  before <- readLines(file.path(project, "DESCRIPTION"))
  expect_error(cmd_add("glue@banana", project = project), "Unsupported")
  writeLines("invalid", file.path(project, "renv.lock"))
  expect_error(cmd_add("newpkg", project = project), "Cannot read")
  expect_equal(readLines(file.path(project, "DESCRIPTION")), before)
  expect_equal(intent_package_request_constraint("glue@>=1.0.0"), ">=1.0.0")
  expect_equal(extract_pkg_name("bioc::Biobase"), "Biobase")
  expect_equal(extract_pkg_name("mypkg=github::owner/repo"), "mypkg")
  expect_equal(
    intent_package_ref_source_class(
      "mypkg=url::https://example.com/pkg.tar.gz"
    ),
    "url"
  )
})

test_that("prune-only snapshots preserve proven seed URLs without carrying changed identities", {
  previous <- list(
    R = list(Repositories = c(RSPM = "https://example.com")),
    Packages = list(
      glue = list(Version = "1.0.0", Source = "Repository", Repository = "RSPM")
    )
  )
  candidate <- list(Packages = previous$Packages)
  result <- intent_preserve_locked_provenance(candidate, previous, character())
  expect_equal(result$Packages$glue$RepositoryURL, "https://example.com")
  expect_null(
    intent_preserve_locked_provenance(
      candidate,
      previous,
      "glue"
    )$Packages$glue$RepositoryURL
  )
  candidate$Packages$glue$Version <- "2.0.0"
  expect_null(
    intent_preserve_locked_provenance(
      candidate,
      previous,
      character()
    )$Packages$glue$RepositoryURL
  )
})

test_that("restore uses the explicit native engine and restores caller options on every exit", {
  withr::local_options(
    renv.config.pak.enabled = TRUE,
    renv.config.repos.override = "https://runner.invalid",
    renv.config.ppm.enabled = TRUE
  )
  withr::local_envvar(RENV_CONFIG_REPOS_OVERRIDE = "https://runner.invalid")
  restore <- backend_restore
  captured <- NULL
  mockery::stub(restore, "renv::restore", function(...) {
    expect_false(getOption("renv.config.pak.enabled"))
    expect_identical(renv::config$repos.override(), character())
    expect_false(renv::config$ppm.enabled())
    captured <<- list(...)
  })
  restore(
    "project",
    c(CRAN = "https://example.com"),
    library = "library",
    lockfile = "candidate.lock",
    clean = FALSE
  )
  expect_true(getOption("renv.config.pak.enabled"))
  expect_equal(
    getOption("renv.config.repos.override"),
    "https://runner.invalid"
  )
  expect_true(getOption("renv.config.ppm.enabled"))
  expect_equal(captured$project, "project")
  expect_equal(captured$library, "library")
  expect_equal(captured$lockfile, "candidate.lock")
  expect_true(captured$transactional)
  expect_false(captured$clean)
  mockery::stub(restore, "renv::restore", function(...) {
    expect_false(getOption("renv.config.pak.enabled"))
    expect_identical(renv::config$repos.override(), character())
    expect_false(renv::config$ppm.enabled())
    stop("restore failed")
  })
  expect_error(restore("project", library = "library"), "restore failed")
  expect_true(getOption("renv.config.pak.enabled"))
  expect_equal(
    getOption("renv.config.repos.override"),
    "https://runner.invalid"
  )
  expect_true(getOption("renv.config.ppm.enabled"))
})

test_that("bare initialization scopes bootstrap repository overrides on every exit", {
  init_backend <- backend_init
  repos <- c(CRAN = "https://project.example", EXTRA = "https://extra.example")
  mockery::stub(init_backend, "renv::init", function(...) {
    expect_equal(
      Sys.getenv("RENV_CONFIG_REPOS_OVERRIDE"),
      "CRAN=https://project.example;EXTRA=https://extra.example"
    )
  })
  withr::local_envvar(RENV_CONFIG_REPOS_OVERRIDE = "https://runner.invalid")
  init_backend("project", repos)
  expect_equal(
    Sys.getenv("RENV_CONFIG_REPOS_OVERRIDE"),
    "https://runner.invalid"
  )
  mockery::stub(init_backend, "renv::init", function(...) {
    stop("bootstrap failed")
  })
  expect_error(init_backend("project", repos), "bootstrap failed")
  expect_equal(
    Sys.getenv("RENV_CONFIG_REPOS_OVERRIDE"),
    "https://runner.invalid"
  )
  Sys.unsetenv("RENV_CONFIG_REPOS_OVERRIDE")
  expect_error(init_backend("project", repos), "bootstrap failed")
  expect_true(is.na(Sys.getenv("RENV_CONFIG_REPOS_OVERRIDE", unset = NA)))
})

test_that("source rebuild removes only affected entries and restores shortcut options", {
  withr::local_options(
    renv.config.cache.enabled = TRUE,
    renv.config.install.shortcuts = TRUE
  )
  restore <- backend_restore
  removed <- NULL
  mockery::stub(restore, "renv::remove", function(packages, project, library) {
    removed <<- list(packages, project, library)
  })
  mockery::stub(restore, "renv::restore", function(...) {
    expect_false(getOption("renv.config.cache.enabled"))
    expect_false(getOption("renv.config.install.shortcuts"))
    stop("download failed")
  })
  expect_error(
    restore("project", library = "library", rebuild = "glue"),
    "download failed"
  )
  expect_equal(removed, list("glue", "project", "library"))
  expect_true(getOption("renv.config.cache.enabled"))
  expect_true(getOption("renv.config.install.shortcuts"))
})

test_that("observed source drift triggers one targeted rebuild before verification", {
  calls <- list()
  local_mocked_bindings(
    backend_restore = function(...) calls[[length(calls) + 1L]] <<- list(...),
    intent_library_drift = function(...) list(sources = "glue"),
    intent_assert_library = function(...) TRUE
  )
  intent_restore_verified(
    "project",
    list(),
    c(CRAN = "https://example.com"),
    TRUE
  )
  expect_length(calls, 2)
  expect_null(calls[[1]]$rebuild)
  expect_equal(calls[[2]]$rebuild, "glue")
})
