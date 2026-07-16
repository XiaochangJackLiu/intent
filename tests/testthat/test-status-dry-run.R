test_that("cmd_status reports manifest, lockfile, and library drift", {
  tmp_dir <- tempfile()
  lib_dir <- tempfile()
  dir.create(tmp_dir)
  dir.create(lib_dir)
  dir.create(file.path(lib_dir, "glue"))
  on.exit(unlink(c(tmp_dir, lib_dir), recursive = TRUE))

  writeLines(
    c(
      "Package: testpkg",
      "Imports:",
      "    glue,",
      "    R6"
    ),
    file.path(tmp_dir, "DESCRIPTION")
  )
  writeLines("{}", file.path(tmp_dir, "renv.lock"))

  mockery::stub(cmd_status, "intent_locked_packages", function(project) {
    c("glue", "rlang")
  })
  mockery::stub(cmd_status, "backend_library", function(project) lib_dir)
  mockery::stub(cmd_status, "intent_library_packages", function(project) {
    "glue"
  })

  current_status <- cmd_status(project = tmp_dir)

  expect_s3_class(current_status, "intent_status")
  expect_setequal(current_status$manifest_packages, c("glue", "R6"))
  expect_setequal(current_status$locked_packages, c("glue", "rlang"))
  expect_equal(current_status$missing_from_lockfile, "R6")
  expect_equal(current_status$extra_in_lockfile, "rlang")
  expect_equal(current_status$missing_from_library, "rlang")
  expect_equal(nrow(current_status$source_violations), 0)
})

test_that("source policy accepts undeclared name via URL matching", {
  lock <- list(
    Packages = list(
      glue = list(
        Version = "1.0.0",
        Source = "Repository",
        Repository = "RSPM",
        RepositoryURL = "https://packagemanager.posit.co/cran/latest"
      )
    )
  )
  policy <- intent_default_source_policy()

  violations <- intent_check_source_policy(
    lock,
    repos = c(CRAN = "https://packagemanager.posit.co/cran/latest"),
    source_policy = policy
  )

  expect_equal(nrow(violations), 0)
})

test_that("source policy flags truly unknown repository names", {
  lock <- list(
    Packages = list(
      pkg = list(
        Version = "1.0.0",
        Source = "Repository",
        Repository = "UnknownRepo"
      )
    )
  )
  policy <- intent_default_source_policy()

  violations <- intent_check_source_policy(
    lock,
    repos = c(CRAN = "https://cran.r-project.org"),
    source_policy = policy
  )

  expect_equal(nrow(violations), 1)
  expect_equal(violations$package, "pkg")
  expect_match(violations$reason, "UnknownRepo")
})

test_that("source policy handles old renv URL-based Repository field", {
  lock <- list(
    Packages = list(
      pkg = list(
        Version = "1.0.0",
        Source = "Repository",
        Repository = "https://cran.r-project.org"
      )
    )
  )
  policy <- intent_default_source_policy()

  violations <- intent_check_source_policy(
    lock,
    repos = c(CRAN = "https://cran.r-project.org"),
    source_policy = policy
  )

  expect_equal(nrow(violations), 0)
})

test_that("source policy exempts tool packages", {
  lock <- list(
    Packages = list(
      intent = list(Version = "0.0.1", Source = "unknown"),
      renv = list(Version = "1.0.0", Source = "unknown"),
      pak = list(Version = "1.0.0", Source = "unknown")
    )
  )
  policy <- intent_default_source_policy()

  violations <- intent_check_source_policy(
    lock,
    repos = character(),
    source_policy = policy
  )

  expect_equal(nrow(violations), 0)
})

test_that("status delegates to command layer", {
  expected <- new_intent_status(
    project = "project",
    manifest_packages = character(),
    locked_packages = character(),
    missing_from_lockfile = character(),
    extra_in_lockfile = character(),
    library_path = "library",
    missing_from_library = character()
  )

  mockery::stub(status, "cmd_status", function(project) expected)

  expect_identical(status(project = "project"), expected)
})

test_that("verify delegates to command layer", {
  expected <- new_intent_verification(
    project = "project",
    ok = TRUE,
    issues = intent_verification_issues_empty(),
    status = new_intent_status(
      project = "project",
      manifest_packages = character(),
      locked_packages = character(),
      missing_from_lockfile = character(),
      extra_in_lockfile = character(),
      library_path = "library",
      missing_from_library = character()
    )
  )

  mockery::stub(verify, "cmd_verify", function(project) expected)

  expect_identical(verify(project = "project"), expected)
})

test_that("doctor delegates to verify", {
  expected <- "verification"
  mockery::stub(doctor, "verify", function(project) expected)

  expect_identical(doctor(project = "project"), expected)
})

test_that("cmd_verify reports missing lockfile", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  writeLines("Package: testpkg", file.path(tmp_dir, "DESCRIPTION"))

  result <- cmd_verify(project = tmp_dir)

  expect_s3_class(result, "intent_verification")
  expect_false(result$ok)
  expect_true(any(result$issues$check == "lockfile"))
  expect_match(
    paste(result$issues$message, collapse = "\n"),
    "renv.lock does not exist",
    fixed = TRUE
  )
})

test_that("verify accepts same-URL repos with different names", {
  lock <- list(
    R = list(
      Repositories = c(RSPM = "https://packagemanager.posit.co/cran/latest")
    )
  )

  issues <- intent_verify_repository_issues(
    lock,
    repos = c(CRAN = "https://packagemanager.posit.co/cran/latest")
  )

  # Same URL, different names -- not a violation
  expect_false(any(grepl("missing repositories", issues$message)))
  expect_false(any(grepl("not declared", issues$message)))
})

test_that("verify flags truly different repository URLs", {
  lock <- list(
    R = list(
      Repositories = c(CRAN = "https://cran.r-project.org")
    )
  )

  issues <- intent_verify_repository_issues(
    lock,
    repos = c(RSPM = "https://packagemanager.posit.co/cran/latest")
  )

  # Different URLs -- real issues
  expect_true(any(grepl("missing repositories", issues$message)))
  expect_true(any(grepl("not declared", issues$message)))
})

test_that("verify flags lockfile packages outside dependency closure", {
  lock <- list(
    Packages = list(
      dplyr = list(Imports = "tibble"),
      tibble = list(Version = "1.0.0"),
      orphan = list(Version = "1.0.0")
    )
  )

  issues <- intent_verify_lockfile_closure_issues(lock, roots = "dplyr")

  expect_equal(issues$check, "lockfile_closure")
  expect_match(issues$message, "orphan")
  expect_false(grepl("tibble", issues$message))
})

test_that("add dry-run returns a plan without mutating DESCRIPTION", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  desc_path <- file.path(tmp_dir, "DESCRIPTION")
  writeLines("Package: testpkg", desc_path)
  before <- readLines(desc_path)

  mockery::stub(cmd_add, "intent_install", function(...) {
    stop("install should not run")
  })
  mockery::stub(cmd_add, "intent_set_project_dep", function(...) {
    stop("manifest update should not run")
  })
  mockery::stub(cmd_add, "intent_snapshot", function(...) {
    stop("snapshot should not run")
  })

  plan <- cmd_add("glue", project = tmp_dir, dry_run = TRUE)

  expect_s3_class(plan, "intent_plan")
  expect_equal(plan$command, "add")
  expect_equal(plan$packages, "glue")
  expect_equal(readLines(desc_path), before)
})

test_that("remove dry-run returns a plan without mutating DESCRIPTION", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  desc_path <- file.path(tmp_dir, "DESCRIPTION")
  writeLines(
    c(
      "Package: testpkg",
      "Imports:",
      "    glue"
    ),
    desc_path
  )
  before <- readLines(desc_path)

  mockery::stub(cmd_remove, "intent_del_project_dep", function(...) {
    stop("manifest update should not run")
  })
  mockery::stub(cmd_remove, "backend_remove", function(...) {
    stop("remove should not run")
  })
  mockery::stub(cmd_remove, "intent_snapshot", function(...) {
    stop("snapshot should not run")
  })
  mockery::stub(cmd_remove, "intent_restore", function(...) {
    stop("restore should not run")
  })

  plan <- cmd_remove("glue", project = tmp_dir, dry_run = TRUE)

  expect_s3_class(plan, "intent_plan")
  expect_equal(plan$command, "remove")
  expect_equal(plan$packages, "glue")
  expect_equal(readLines(desc_path), before)
})

test_that("sync dry-run returns planned work without backend mutation", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  writeLines(
    c(
      "Package: testpkg",
      "Imports:",
      "    glue"
    ),
    file.path(tmp_dir, "DESCRIPTION")
  )

  mockery::stub(cmd_sync, "intent_install", function(...) {
    stop("install should not run")
  })
  mockery::stub(cmd_sync, "intent_snapshot", function(...) {
    stop("snapshot should not run")
  })
  mockery::stub(cmd_sync, "intent_restore", function(...) {
    stop("restore should not run")
  })

  plan <- cmd_sync(project = tmp_dir, dry_run = TRUE)

  expect_s3_class(plan, "intent_plan")
  expect_equal(plan$command, "sync")
  expect_equal(plan$packages, "glue")
  expect_true("would_restore" %in% plan$actions)
})

test_that("as.character.intent_status returns valid JSON", {
  obj <- new_intent_status(
    project = "/path/to/project",
    manifest_packages = c("dplyr", "glue"),
    locked_packages = c("dplyr", "glue", "R6"),
    missing_from_lockfile = character(),
    extra_in_lockfile = "R6",
    library_path = "/path/to/library",
    missing_from_library = "R6"
  )

  json_str <- as.character(obj)
  parsed <- jsonlite::fromJSON(json_str)

  expect_equal(parsed$project, "/path/to/project")
  expect_equal(parsed$manifest_packages, c("dplyr", "glue"))
  expect_length(parsed$missing_from_lockfile, 0)
  expect_equal(parsed$extra_in_lockfile, "R6")
  expect_named(
    parsed,
    c(
      "project",
      "manifest_packages",
      "locked_packages",
      "missing_from_lockfile",
      "extra_in_lockfile",
      "library_path",
      "missing_from_library",
      "source_policy",
      "source_violations",
      "r_version",
      "r_constraint",
      "lockfile_r_version"
    )
  )
})

test_that("as.character.intent_plan returns valid JSON", {
  obj <- new_intent_plan(
    project = "/path/to/project",
    command = "add",
    actions = c(
      "would_install: dplyr",
      "would_update_manifest: Imports",
      "would_snapshot"
    ),
    packages = "dplyr"
  )

  json_str <- as.character(obj)
  parsed <- jsonlite::fromJSON(json_str)

  expect_equal(parsed$project, "/path/to/project")
  expect_equal(parsed$command, "add")
  expect_equal(parsed$packages, "dplyr")
  expect_length(parsed$actions, 3)
})

test_that("as.character.intent_verification returns valid JSON", {
  obj <- new_intent_verification(
    project = "/path/to/project",
    ok = FALSE,
    issues = intent_verification_issue("lockfile", "error", "missing"),
    status = new_intent_status(
      project = "/path/to/project",
      manifest_packages = "glue",
      locked_packages = character(),
      missing_from_lockfile = "glue",
      extra_in_lockfile = character(),
      library_path = "/path/to/library",
      missing_from_library = character()
    )
  )

  json_str <- as.character(obj)
  parsed <- jsonlite::fromJSON(json_str)

  expect_false(parsed$ok)
  expect_equal(parsed$issues$check, "lockfile")
  expect_equal(parsed$status$missing_from_lockfile, "glue")
})

test_that("intent_supplement_repositories appends undeclared name via record URL", {
  lock <- list(
    R = list(
      Repositories = c(CRAN = "https://packagemanager.posit.co/cran/latest")
    ),
    Packages = list(
      dplyr = list(
        Version = "1.0.0",
        Repository = "RSPM",
        RepositoryURL = "https://packagemanager.posit.co/cran/latest"
      )
    )
  )

  result <- intent_supplement_repositories(
    lock,
    repos = c(CRAN = "https://packagemanager.posit.co/cran/latest")
  )

  expect_true("CRAN" %in% names(result$R$Repositories))
  expect_true("RSPM" %in% names(result$R$Repositories))
  expect_equal(
    result$R$Repositories[["RSPM"]],
    "https://packagemanager.posit.co/cran/latest"
  )
})

test_that("intent_supplement_repositories skips URL-type Repository fields", {
  lock <- list(
    R = list(
      Repositories = c(CRAN = "https://cran.r-project.org")
    ),
    Packages = list(
      pkg = list(
        Version = "1.0.0",
        Repository = "https://cran.r-project.org"
      )
    )
  )

  result <- intent_supplement_repositories(
    lock,
    repos = c(CRAN = "https://cran.r-project.org")
  )

  # No supplementation -- URL-type is skipped
  expect_equal(names(result$R$Repositories), "CRAN")
})

test_that("intent_supplement_repositories messages on undeclared known name", {
  lock <- list(
    R = list(
      Repositories = c(CRAN = "https://packagemanager.posit.co/cran/latest")
    ),
    Packages = list(
      dplyr = list(
        Version = "1.0.0",
        Repository = "RSPM"
        # No RepositoryURL -- can't resolve via URL, must message user
      )
    )
  )

  expect_message(
    result <- intent_supplement_repositories(
      lock,
      repos = c(CRAN = "https://packagemanager.posit.co/cran/latest")
    ),
    "RSPM"
  )

  # RSPM is NOT silently supplemented
  expect_false("RSPM" %in% names(result$R$Repositories))
})

test_that("intent_supplement_repositories is no-op when name already present", {
  lock <- list(
    R = list(
      Repositories = c(RSPM = "https://packagemanager.posit.co/cran/latest")
    ),
    Packages = list(
      dplyr = list(
        Version = "1.0.0",
        Repository = "RSPM"
      )
    )
  )

  result <- intent_supplement_repositories(
    lock,
    repos = c(RSPM = "https://packagemanager.posit.co/cran/latest")
  )

  expect_equal(names(result$R$Repositories), "RSPM")
})

test_that("intent_check_repository_policy resolves undeclared name via URL", {
  row <- data.frame(
    repository = "RSPM",
    repository_url = "https://packagemanager.posit.co/cran/latest",
    package = "dplyr",
    source = "repository",
    stringsAsFactors = FALSE
  )

  violations <- intent_check_repository_policy(
    row,
    repos = c(CRAN = "https://packagemanager.posit.co/cran/latest")
  )

  expect_equal(nrow(violations), 0)
})

test_that("intent_check_repository_policy flags undeclared name with mismatched URL", {
  row <- data.frame(
    repository = "RSPM",
    repository_url = "https://some-other-server.example.com",
    package = "dplyr",
    source = "repository",
    stringsAsFactors = FALSE
  )

  violations <- intent_check_repository_policy(
    row,
    repos = c(CRAN = "https://packagemanager.posit.co/cran/latest")
  )

  expect_equal(nrow(violations), 1)
  expect_match(violations$reason, "URL does not match")
})

test_that("intent_check_repository_policy flags undeclared name without repository_url", {
  row <- data.frame(
    repository = "UnknownRepo",
    repository_url = NA_character_,
    package = "pkg",
    source = "repository",
    stringsAsFactors = FALSE
  )

  violations <- intent_check_repository_policy(
    row,
    repos = c(CRAN = "https://cran.r-project.org")
  )

  expect_equal(nrow(violations), 1)
  expect_match(violations$reason, "not declared")
})
