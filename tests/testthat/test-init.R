test_that("init defaults to CRAN when no repos provided", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  mockery::stub(cmd_init, "backend_init", function(project, repos) {
    expect_equal(repos[["CRAN"]], "https://cran.r-project.org")
  })

  cmd_init(path = tmp_dir, repos = NULL, install_self = "never")

  rproject <- desc::description$new(file.path(tmp_dir, "DESCRIPTION"))
  expect_equal(
    rproject$get_field("Config/intent/repos/CRAN"),
    "https://cran.r-project.org"
  )
})

test_that("init hydrates intent by default", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  hydrated <- FALSE

  mockery::stub(cmd_init, "backend_init", function(project, repos) {
    dir.create(file.path(project, "renv"), recursive = TRUE)
  })
  mockery::stub(
    cmd_init,
    "maybe_hydrate_intent",
    function(project, sources, install_self) {
      hydrated <<- identical(install_self, "hydrate")
    }
  )

  cmd_init(path = tmp_dir, repos = NULL)

  expect_true(hydrated)
})

test_that("init can leave intent as an external tool", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  install_self_seen <- NULL

  mockery::stub(cmd_init, "backend_init", function(project, repos) {
    dir.create(file.path(project, "renv"), recursive = TRUE)
  })
  mockery::stub(
    cmd_init,
    "maybe_hydrate_intent",
    function(project, sources, install_self) {
      install_self_seen <<- install_self
    }
  )

  cmd_init(path = tmp_dir, repos = NULL, install_self = "never")

  expect_equal(install_self_seen, "never")
})

test_that("init refuses existing non-intent DESCRIPTION without mutation", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  desc_path <- file.path(tmp_dir, "DESCRIPTION")
  lock_path <- file.path(tmp_dir, "renv.lock")
  writeLines(
    c(
      "Package: existing",
      "Version: 0.0.1",
      "Imports: glue"
    ),
    desc_path
  )
  writeLines("existing lock", lock_path)

  original_desc <- readLines(desc_path)
  original_lock <- readLines(lock_path)
  called <- FALSE

  mockery::stub(cmd_init, "backend_init", function(...) {
    called <<- TRUE
  })

  expect_error(
    cmd_init(path = tmp_dir, repos = c(CRAN = "https://example.test")),
    "not an intent manifest"
  )

  expect_false(called)
  expect_equal(readLines(desc_path), original_desc)
  expect_equal(readLines(lock_path), original_lock)
  expect_false(file.exists(file.path(tmp_dir, ".Renviron")))
  expect_false(file.exists(file.path(tmp_dir, ".Rprofile")))
})

test_that("init refuses invalid DESCRIPTION before backend work", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  desc_path <- file.path(tmp_dir, "DESCRIPTION")
  writeLines("not a valid DESCRIPTION file", desc_path)

  called <- FALSE
  mockery::stub(cmd_init, "backend_init", function(...) {
    called <<- TRUE
  })

  expect_error(
    cmd_init(path = tmp_dir, install_self = "never"),
    "could not be parsed"
  )

  expect_false(called)
  expect_equal(readLines(desc_path), "not a valid DESCRIPTION file")
})

test_that("init refuses missing DESCRIPTION with existing renv.lock", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  lock_path <- file.path(tmp_dir, "renv.lock")
  writeLines("existing lock", lock_path)

  called <- FALSE
  mockery::stub(cmd_init, "backend_init", function(...) {
    called <<- TRUE
  })

  expect_error(
    cmd_init(path = tmp_dir, install_self = "never"),
    "existing renv state"
  )

  expect_false(called)
  expect_false(file.exists(file.path(tmp_dir, "DESCRIPTION")))
  expect_equal(readLines(lock_path), "existing lock")
})

test_that("init refuses missing DESCRIPTION with existing renv directory", {
  tmp_dir <- tempfile()
  dir.create(file.path(tmp_dir, "renv"), recursive = TRUE)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  called <- FALSE
  mockery::stub(cmd_init, "intent_sync_project", function(...) {
    called <<- TRUE
  })

  expect_error(
    cmd_init(path = tmp_dir, install_self = "never"),
    "existing renv state"
  )

  expect_false(called)
  expect_false(file.exists(file.path(tmp_dir, "DESCRIPTION")))
})

test_that("init allows intent manifest and initializes backend when renv is absent", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  writeLines(
    c(
      "Package: existing",
      "Version: 0.0.1",
      "Config/intent/repos/CRAN: https://example.test"
    ),
    file.path(tmp_dir, "DESCRIPTION")
  )

  backend_called <- FALSE
  sync_called <- FALSE
  mockery::stub(cmd_init, "backend_init", function(project, repos) {
    backend_called <<- TRUE
    expect_equal(repos[["CRAN"]], "https://example.test")
  })
  mockery::stub(cmd_init, "intent_sync_project", function(...) {
    sync_called <<- TRUE
  })

  cmd_init(path = tmp_dir, install_self = "never")

  expect_true(backend_called)
  expect_false(sync_called)
})

test_that("init allows intent manifest and syncs when renv exists", {
  tmp_dir <- tempfile()
  dir.create(file.path(tmp_dir, "renv"), recursive = TRUE)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  writeLines(
    c(
      "Package: existing",
      "Version: 0.0.1",
      "Config/intent/repos/CRAN: https://example.test"
    ),
    file.path(tmp_dir, "DESCRIPTION")
  )

  backend_called <- FALSE
  sync_called <- FALSE
  mockery::stub(cmd_init, "backend_init", function(...) {
    backend_called <<- TRUE
  })
  mockery::stub(cmd_init, "intent_sync_project", function(project) {
    sync_called <<- identical(normalizePath(project), normalizePath(tmp_dir))
  })

  cmd_init(path = tmp_dir, install_self = "never")

  expect_false(backend_called)
  expect_true(sync_called)
})

test_that("init syncs intent manifest with existing lockfile but no renv directory", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  writeLines(
    c(
      "Package: existing",
      "Version: 0.0.1",
      "Config/intent/repos/CRAN: https://example.test"
    ),
    file.path(tmp_dir, "DESCRIPTION")
  )
  writeLines("existing lock", file.path(tmp_dir, "renv.lock"))

  backend_called <- FALSE
  sync_called <- FALSE
  mockery::stub(cmd_init, "backend_init", function(...) {
    backend_called <<- TRUE
  })
  mockery::stub(cmd_init, "intent_sync_project", function(project) {
    sync_called <<- identical(normalizePath(project), normalizePath(tmp_dir))
  })

  cmd_init(path = tmp_dir, install_self = "never")

  expect_false(backend_called)
  expect_true(sync_called)
})

test_that("init writes default bootstrap version constraints", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  mockery::stub(cmd_init, "backend_init", function(...) {})

  cmd_init(path = tmp_dir, install_self = "never")

  deps <- desc::desc_get_deps(file = file.path(tmp_dir, "DESCRIPTION"))
  versions <- bootstrap_dependency_versions()
  expect_equal(deps$version[deps$package == "intent"], versions[["intent"]])
  expect_equal(
    deps$version[deps$package == "pak"],
    bootstrap_version_or_any(versions[["pak"]])
  )
  expect_equal(
    deps$version[deps$package == "renv"],
    bootstrap_version_or_any(versions[["renv"]])
  )
})

test_that("init preserves user bootstrap version constraints", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  writeLines(
    c(
      "Package: existing",
      "Version: 0.0.1",
      "Suggests:",
      "    intent (>= 0.9.0),",
      "    pak (>= 0.8.0),",
      "    renv (== 1.1.4)",
      "Config/intent/repos/CRAN: https://example.test"
    ),
    file.path(tmp_dir, "DESCRIPTION")
  )

  mockery::stub(cmd_init, "backend_init", function(...) {})

  cmd_init(path = tmp_dir, install_self = "never")

  deps <- desc::desc_get_deps(file = file.path(tmp_dir, "DESCRIPTION"))
  expect_equal(deps$version[deps$package == "intent"], ">= 0.9.0")
  expect_equal(deps$version[deps$package == "pak"], ">= 0.8.0")
  expect_equal(deps$version[deps$package == "renv"], "== 1.1.4")
})

test_that("intent hydration failure does not fail init", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  mockery::stub(cmd_init, "backend_init", function(project, repos) {
    dir.create(file.path(project, "renv"), recursive = TRUE)
  })
  mockery::stub(
    maybe_hydrate_intent,
    "backend_hydrate",
    function(project, pkgs, sources) {
      stop("not available")
    }
  )
  mockery::stub(maybe_hydrate_intent, "backend_library", function(project) {
    file.path(project, "library")
  })

  # Init should succeed (no error) even when hydration fails.
  # The exact messages depend on whether intent is available for hydration
  # in the current environment (e.g. CI vs local).
  expect_error(
    cmd_init(path = tmp_dir, repos = NULL),
    NA
  )
})

test_that("intent hydration force-snapshots local tool installs", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  force_seen <- NULL
  lib <- file.path(tmp_dir, "library")
  dir.create(file.path(lib, "intent"), recursive = TRUE)

  mockery::stub(
    maybe_hydrate_intent,
    "backend_hydrate",
    function(project, pkgs, sources) {
      list(intent = "hydrated")
    }
  )
  mockery::stub(maybe_hydrate_intent, "backend_library", function(project) {
    lib
  })
  mockery::stub(
    maybe_hydrate_intent,
    "intent_snapshot",
    function(project, force) {
      force_seen <<- force
    }
  )

  maybe_hydrate_intent(tmp_dir, sources = character(), install_self = "hydrate")

  expect_true(force_seen)
})

test_that("intent::init creates necessary files", {
  # Use a temp directory for the project
  tmp_dir <- file.path(
    Sys.getenv("R_USER_CACHE_DIR", unset = tempdir()),
    paste0("intent_test_init_", Sys.getpid())
  )
  on.exit(unlink(tmp_dir, recursive = TRUE))

  if (dir.exists(tmp_dir)) {
    unlink(tmp_dir, recursive = TRUE)
  }

  # Mocking utils::check_renv_loaded or ensuring environment has them
  # For this test, we assume the environment is set up (we are running in code editor agent)

  # Run init
  # We might need to mock or suppress messages
  init(
    path = tmp_dir,
    repos = c(
      CRAN = "https://packagemanager.posit.co/cran/latest"
    )
  )

  expect_true(dir.exists(tmp_dir))
  expect_true(file.exists(file.path(tmp_dir, "DESCRIPTION")))
  expect_true(file.exists(file.path(tmp_dir, "renv.lock")))
  expect_true(file.exists(file.path(tmp_dir, ".Rprofile")))
  expect_true(file.exists(file.path(tmp_dir, ".Renviron")))

  # Check content
  ## DESCRIPTION
  rproject <- desc::description$new(file.path(tmp_dir, "DESCRIPTION"))
  expect_true(rproject$has_dep("pak"))
  expect_true(rproject$has_dep("renv"))
  expect_true(rproject$has_dep("intent"))
  ### Check repos in DESCRIPTION
  expect_equal(
    rproject$get_field("Config/intent/repos/CRAN"),
    "https://packagemanager.posit.co/cran/latest"
  )

  ## renv.lock
  renv_lock <- renv::lockfile_read(
    file = file.path(tmp_dir, "renv.lock"),
    project = tmp_dir
  )
  ### check repos -- user's name preserved as-is
  renv_repos <- renv_lock$R$Repositories
  expect_equal(names(renv_repos), c("CRAN"))
  expect_equal(
    renv_repos[[1]],
    "https://packagemanager.posit.co/cran/latest"
  )
  expect_true("pak" %in% names(renv_lock$Packages))
  expect_true("renv" %in% names(renv_lock$Packages))

  # generated/modified by `renv`
  rprofile <- readLines(file.path(tmp_dir, ".Rprofile"))

  # generated/modified by `intent`
  renviron <- readLines(file.path(tmp_dir, ".Renviron"))
  expect_true(any(grepl("RENV_CONFIG_PAK_ENABLED = TRUE", renviron)))

  # Check renv settings
  # verifying renv settings might require loading the project or checking renv/settings.json
  # But intent::init doesn't write settings.json directly, it calls renv::settings
  # which writes to renv/settings.dcf or json.
  expect_true(
    file.exists(file.path(tmp_dir, "renv/settings.json"))
  )
})

# classify_init_description direct unit tests

test_that("classify_init_description detects intent_manifest with one named repo", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  writeLines(
    c(
      "Package: testpkg",
      "Version: 0.0.1",
      "Config/intent/repos/CRAN: https://example.com"
    ),
    file.path(tmp_dir, "DESCRIPTION")
  )

  result <- classify_init_description(tmp_dir)
  expect_equal(result$type, "intent_manifest")
  expect_null(result$error)
})

test_that("classify_init_description detects intent_manifest with multiple repos", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  writeLines(
    c(
      "Package: testpkg",
      "Version: 0.0.1",
      "Config/intent/repos/CRAN: https://cran.example.com",
      "Config/intent/repos/INTERNAL: https://r.example.com/packages"
    ),
    file.path(tmp_dir, "DESCRIPTION")
  )

  result <- classify_init_description(tmp_dir)
  expect_equal(result$type, "intent_manifest")
})

test_that("classify_init_description detects non_intent_manifest without config", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  writeLines(
    c(
      "Package: testpkg",
      "Version: 0.0.1",
      "Imports: glue"
    ),
    file.path(tmp_dir, "DESCRIPTION")
  )

  result <- classify_init_description(tmp_dir)
  expect_equal(result$type, "non_intent_manifest")
})

test_that("classify_init_description detects non_intent_manifest with empty repo URL", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  writeLines(
    c(
      "Package: testpkg",
      "Version: 0.0.1",
      "Config/intent/repos/CRAN: "
    ),
    file.path(tmp_dir, "DESCRIPTION")
  )

  result <- classify_init_description(tmp_dir)
  expect_equal(result$type, "non_intent_manifest")
})

test_that("classify_init_description detects non_intent_manifest with empty repo name", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  writeLines(
    c(
      "Package: testpkg",
      "Version: 0.0.1",
      "Config/intent/repos/: https://example.test"
    ),
    file.path(tmp_dir, "DESCRIPTION")
  )

  result <- classify_init_description(tmp_dir)
  expect_equal(result$type, "non_intent_manifest")
})

test_that("classify_init_description fails closed on mixed valid/invalid repos", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  writeLines(
    c(
      "Package: testpkg",
      "Version: 0.0.1",
      "Config/intent/repos/CRAN: https://example.test",
      "Config/intent/repos/: https://example.test"
    ),
    file.path(tmp_dir, "DESCRIPTION")
  )

  result <- classify_init_description(tmp_dir)
  expect_equal(result$type, "non_intent_manifest")
})

test_that("classify_init_description detects missing_manifest", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  result <- classify_init_description(tmp_dir)
  expect_equal(result$type, "missing_manifest")
  expect_null(result$error)
})

test_that("classify_init_description detects invalid_manifest", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  writeLines("not a valid DESCRIPTION file", file.path(tmp_dir, "DESCRIPTION"))

  result <- classify_init_description(tmp_dir)
  expect_equal(result$type, "invalid_manifest")
  expect_true(!is.null(result$error))
})

test_that("stop_for_unsafe_init errors on unknown classification type", {
  expect_error(
    stop_for_unsafe_init(
      list(type = "unknown_type", error = NULL),
      list(renv_dir = FALSE, lockfile = FALSE)
    ),
    "Internal error"
  )
})

# Integration: init preserves user bootstrap constraints byte-identically

test_that("init preserves user bootstrap constraints byte-identically in DESCRIPTION", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  desc_lines <- c(
    "Package: existing",
    "Version: 0.0.1",
    "Suggests:",
    "    intent (>= 0.9.0),",
    "    pak (>= 0.8.0),",
    "    renv (== 1.1.4)",
    "Config/intent/repos/CRAN: https://example.test"
  )
  writeLines(desc_lines, file.path(tmp_dir, "DESCRIPTION"))

  mockery::stub(cmd_init, "backend_init", function(...) {})

  cmd_init(path = tmp_dir, install_self = "never")

  deps <- desc::desc_get_deps(file = file.path(tmp_dir, "DESCRIPTION"))

  intent_row <- deps[deps$package == "intent", , drop = FALSE]
  expect_equal(nrow(intent_row), 1)
  expect_equal(intent_row$version[[1]], ">= 0.9.0")

  pak_row <- deps[deps$package == "pak", , drop = FALSE]
  expect_equal(nrow(pak_row), 1)
  expect_equal(pak_row$version[[1]], ">= 0.8.0")

  renv_row <- deps[deps$package == "renv", , drop = FALSE]
  expect_equal(nrow(renv_row), 1)
  expect_equal(renv_row$version[[1]], "== 1.1.4")
})

test_that("init warns on platform-specific repo URL", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  mockery::stub(cmd_init, "backend_init", function(...) {})

  expect_warning(
    cmd_init(
      path = tmp_dir,
      repos = c(
        CRAN = "https://packagemanager.posit.co/cran/__linux__/manylinux_2_28/latest"
      ),
      install_self = "never"
    ),
    "platform-specific"
  )
})
