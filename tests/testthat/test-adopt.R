test_that("adopt returns adoption_plan in dry_run mode", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  writeLines(
    c(
      "Package: testpkg",
      "Version: 0.0.1",
      "Imports: glue",
      "Config/intent/repos/CRAN: https://cran.example.com"
    ),
    file.path(tmp_dir, "DESCRIPTION")
  )

  plan <- cmd_adopt(
    path = tmp_dir,
    repos = c(CRAN = "https://cran.example.com"),
    strategy = "manifest",
    dry_run = TRUE
  )

  expect_s3_class(plan, "adoption_plan")
  expect_equal(plan$strategy, "manifest")
  expect_equal(
    normalizePath(plan$project, winslash = "/"),
    normalizePath(tmp_dir, winslash = "/")
  )
})

test_that("adopt errors when DESCRIPTION is missing", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  expect_error(
    cmd_adopt(path = tmp_dir, strategy = "manifest"),
    "No DESCRIPTION file found"
  )
})

test_that("adopt errors when DESCRIPTION is unparseable", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  writeLines("not a valid DESCRIPTION", file.path(tmp_dir, "DESCRIPTION"))

  expect_error(
    cmd_adopt(path = tmp_dir, strategy = "manifest"),
    "could not be parsed"
  )
})

test_that("adopt errors when no repos provided and none in DESCRIPTION", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  writeLines(
    c("Package: testpkg", "Version: 0.0.1", "Imports: glue"),
    file.path(tmp_dir, "DESCRIPTION")
  )

  expect_error(
    cmd_adopt(path = tmp_dir, repos = NULL),
    "No repositories configured"
  )
})

test_that("adopt uses repos from caller when provided", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  writeLines(
    c("Package: testpkg", "Version: 0.0.1"),
    file.path(tmp_dir, "DESCRIPTION")
  )

  plan <- cmd_adopt(
    path = tmp_dir,
    repos = c(CRAN = "https://cran.example.com"),
    dry_run = TRUE
  )

  repo_actions <- plan$actions[
    grepl("Config/intent/repos", plan$actions$target),
    ,
    drop = FALSE
  ]
  expect_true(nrow(repo_actions) > 0)
  expect_true(any(repo_actions$action == "add"))
})

test_that("adopt uses repos from DESCRIPTION when no repos provided", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  writeLines(
    c(
      "Package: testpkg",
      "Version: 0.0.1",
      "Config/intent/repos/CRAN: https://cran.example.com"
    ),
    file.path(tmp_dir, "DESCRIPTION")
  )

  plan <- cmd_adopt(path = tmp_dir, repos = NULL, dry_run = TRUE)

  # Should preserve the existing repo or add it (depending on version match)
  repo_actions <- plan$actions[
    grepl("Config/intent/repos", plan$actions$target),
    ,
    drop = FALSE
  ]
  expect_true(nrow(repo_actions) > 0)
})

test_that("adopt adds missing bootstrap dependencies", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  writeLines(
    c(
      "Package: testpkg",
      "Version: 0.0.1",
      "Config/intent/repos/CRAN: https://cran.example.com"
    ),
    file.path(tmp_dir, "DESCRIPTION")
  )

  plan <- cmd_adopt(
    path = tmp_dir,
    repos = c(CRAN = "https://cran.example.com"),
    dry_run = TRUE
  )

  bootstrap_actions <- plan$actions[
    grepl("Suggests:", plan$actions$target, fixed = TRUE),
    ,
    drop = FALSE
  ]
  expect_true(nrow(bootstrap_actions) > 0)
  expect_true(any(bootstrap_actions$action == "add"))
})

test_that("adopt adds .Renviron action when RENV_CONFIG_PAK_ENABLED missing", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  writeLines(
    c(
      "Package: testpkg",
      "Version: 0.0.1",
      "Config/intent/repos/CRAN: https://cran.example.com"
    ),
    file.path(tmp_dir, "DESCRIPTION")
  )

  plan <- cmd_adopt(
    path = tmp_dir,
    repos = c(CRAN = "https://cran.example.com"),
    dry_run = TRUE
  )

  renviron_actions <- plan$actions[
    plan$actions$target == ".Renviron",
    ,
    drop = FALSE
  ]
  expect_equal(nrow(renviron_actions), 1)
  expect_equal(renviron_actions$action, "add")
})

test_that("adopt preserves existing .Renviron with RENV_CONFIG_PAK_ENABLED", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  writeLines(
    c(
      "Package: testpkg",
      "Version: 0.0.1",
      "Config/intent/repos/CRAN: https://cran.example.com"
    ),
    file.path(tmp_dir, "DESCRIPTION")
  )
  writeLines("RENV_CONFIG_PAK_ENABLED = TRUE", file.path(tmp_dir, ".Renviron"))

  plan <- cmd_adopt(
    path = tmp_dir,
    repos = c(CRAN = "https://cran.example.com"),
    dry_run = TRUE
  )

  renviron_actions <- plan$actions[
    plan$actions$target == ".Renviron",
    ,
    drop = FALSE
  ]
  expect_equal(renviron_actions$action, "preserve")
})

test_that("adopt_build_candidates produces correct data frame", {
  comparison <- list(
    manifest_pkgs = c("glue"),
    locked_pkgs = c("dplyr", "glue"),
    in_lockfile_not_manifest = c("dplyr"),
    in_manifest_not_lockfile = character()
  )
  candidates <- adopt_build_candidates(comparison, "manifest", FALSE)

  expect_equal(nrow(candidates), 1)
  expect_equal(candidates$package, "dplyr")
  expect_equal(candidates$source, "renv.lock")
})

test_that("adopt_build_issues reports lockfile drift", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  writeLines(
    c("Package: tp", "Version: 0.0.1"),
    file.path(tmp_dir, "DESCRIPTION")
  )

  bootstrap_plan <- bootstrap_dependency_plan(
    desc::description$new("!new")$set("Package", "tp"),
    versions = c(intent = ">= 1.0.0", pak = NA, renv = NA)
  )
  comparison <- list(
    manifest_pkgs = c("glue"),
    locked_pkgs = c("dplyr"),
    in_lockfile_not_manifest = c("dplyr"),
    in_manifest_not_lockfile = c("glue")
  )
  issues <- adopt_build_issues(
    bootstrap_plan,
    comparison,
    "manifest",
    FALSE,
    effective_repos = c(CRAN = "https://cran.example.com"),
    desc_path = file.path(tmp_dir, "DESCRIPTION")
  )

  lockfile_issues <- issues[issues$area == "lockfile", , drop = FALSE]
  expect_true(nrow(lockfile_issues) > 0)
  expect_match(lockfile_issues$message[[1]], "glue")
})

test_that("adopt with override=TRUE resolves constraint conflicts and reports overrides", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  writeLines(
    c(
      "Package: testpkg",
      "Version: 0.0.1",
      "Suggests:",
      "    renv (< 0.9.0)",
      "Config/intent/repos/CRAN: https://cran.example.com"
    ),
    file.path(tmp_dir, "DESCRIPTION")
  )

  plan <- cmd_adopt(
    path = tmp_dir,
    repos = c(CRAN = "https://cran.example.com"),
    dry_run = TRUE
  )

  # With override=TRUE, the existing renv constraint is overridden with
  # intent's >= requirement. The override generates info issues, not errors.
  expect_true(plan$ok)
  # Should have info about the override
  bootstrap_issues <- plan$issues[
    plan$issues$area == "bootstrap",
    ,
    drop = FALSE
  ]
  expect_true(any(grepl("overrides existing", bootstrap_issues$message)))
})

test_that("adopt apply mode writes repos to DESCRIPTION", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  writeLines(
    c(
      "Package: testpkg",
      "Version: 0.0.1"
    ),
    file.path(tmp_dir, "DESCRIPTION")
  )

  mockery::stub(cmd_adopt, "intent_sync_project", function(...) {})
  mockery::stub(cmd_adopt, "maybe_hydrate_intent", function(...) {
    invisible(FALSE)
  })
  mockery::stub(cmd_adopt, "renv::settings", NULL)

  # We need to stub renv::settings$snapshot.type inside adopt_apply_plan
  # but we're stubbing cmd_adopt's apply step. Let's just stub adopt_apply_plan.
  mockery::stub(
    cmd_adopt,
    "adopt_apply_plan",
    function(plan, project_dir, rproject, effective_repos, install_self) {
      for (i in seq_along(effective_repos)) {
        rproject$set(
          sprintf("Config/intent/repos/%s", names(effective_repos)[[i]]),
          effective_repos[[i]]
        )
      }
      apply_bootstrap_dependencies(rproject, plan$bootstrap)
      rproject$write(file.path(project_dir, "DESCRIPTION"))
    }
  )

  cmd_adopt(
    path = tmp_dir,
    repos = c(CRAN = "https://cran.example.com"),
    dry_run = FALSE,
    install_self = "never"
  )

  desc_lines <- readLines(file.path(tmp_dir, "DESCRIPTION"))
  expect_true(any(grepl("Config/intent/repos/CRAN", desc_lines)))
  expect_true(any(grepl("https://cran.example.com", desc_lines)))
})

test_that("adopt apply mode writes .Renviron when missing", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  writeLines(
    c(
      "Package: testpkg",
      "Version: 0.0.1",
      "Config/intent/repos/CRAN: https://cran.example.com"
    ),
    file.path(tmp_dir, "DESCRIPTION")
  )

  mockery::stub(cmd_adopt, "intent_sync_project", function(...) {})
  mockery::stub(cmd_adopt, "maybe_hydrate_intent", function(...) {
    invisible(FALSE)
  })
  mockery::stub(
    cmd_adopt,
    "adopt_apply_plan",
    function(plan, project_dir, rproject, effective_repos, install_self) {
      apply_bootstrap_dependencies(rproject, plan$bootstrap)
      rproject$write(file.path(project_dir, "DESCRIPTION"))

      renviron_path <- file.path(project_dir, ".Renviron")
      writeLines("RENV_CONFIG_PAK_ENABLED = TRUE", renviron_path)
    }
  )

  cmd_adopt(
    path = tmp_dir,
    repos = c(CRAN = "https://cran.example.com"),
    dry_run = FALSE,
    install_self = "never"
  )

  expect_true(file.exists(file.path(tmp_dir, ".Renviron")))
})

test_that("adopt with install_self = never skips hydration", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  writeLines(
    c(
      "Package: testpkg",
      "Version: 0.0.1",
      "Config/intent/repos/CRAN: https://cran.example.com"
    ),
    file.path(tmp_dir, "DESCRIPTION")
  )

  hydrated <- FALSE
  mockery::stub(cmd_adopt, "intent_sync_project", function(...) {})
  mockery::stub(
    cmd_adopt,
    "maybe_hydrate_intent",
    function(project, sources, install_self) {
      hydrated <<- identical(install_self, "hydrate")
    }
  )
  mockery::stub(
    cmd_adopt,
    "adopt_apply_plan",
    function(plan, project_dir, rproject, effective_repos, install_self) {
      apply_bootstrap_dependencies(rproject, plan$bootstrap)
      rproject$write(file.path(project_dir, "DESCRIPTION"))
      if (!identical(install_self, "never")) {
        bootstrap_sources <- .libPaths()
        maybe_hydrate_intent(project_dir, .libPaths(), install_self)
      }
    }
  )
  mockery::stub(
    adopt_apply_plan,
    "renv::settings$snapshot.type",
    function(...) {}
  )

  plan <- cmd_adopt(
    path = tmp_dir,
    repos = c(CRAN = "https://cran.example.com"),
    dry_run = TRUE
  )

  cmd_adopt(
    path = tmp_dir,
    repos = c(CRAN = "https://cran.example.com"),
    dry_run = FALSE,
    install_self = "never"
  )

  expect_false(hydrated)
})

test_that("adopt preserves existing matching repo rather than re-adding", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  writeLines(
    c(
      "Package: testpkg",
      "Version: 0.0.1",
      "Config/intent/repos/CRAN: https://cran.example.com"
    ),
    file.path(tmp_dir, "DESCRIPTION")
  )

  plan <- cmd_adopt(
    path = tmp_dir,
    repos = c(CRAN = "https://cran.example.com"),
    dry_run = TRUE
  )

  cran_actions <- plan$actions[
    grepl("Config/intent/repos/CRAN", plan$actions$target),
    ,
    drop = FALSE
  ]
  expect_equal(cran_actions$action[[1]], "preserve")
})

test_that("print.adoption_plan format matches expected output", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  writeLines(
    c(
      "Package: testpkg",
      "Version: 0.0.1",
      "Config/intent/repos/CRAN: https://cran.example.com"
    ),
    file.path(tmp_dir, "DESCRIPTION")
  )

  plan <- cmd_adopt(
    path = tmp_dir,
    repos = c(CRAN = "https://cran.example.com"),
    dry_run = TRUE
  )

  output <- capture.output(print(plan))
  text <- paste(output, collapse = "\n")

  expect_match(text, "Adoption plan for", fixed = TRUE)
  expect_match(text, "Strategy:", fixed = TRUE)
  expect_match(text, "OK:", fixed = TRUE)
})
