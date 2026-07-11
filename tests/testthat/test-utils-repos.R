test_that("load_intent_repos returns repos without setting options", {
  tmp_dir <- file.path(
    Sys.getenv("R_USER_CACHE_DIR", unset = tempdir()),
    paste0("intent_test_utils_repos_", Sys.getpid())
  )
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  desc_path <- file.path(tmp_dir, "DESCRIPTION")
  writeLines(
    c(
      "Package: testpkg",
      "Config/intent/repos/TEST: https://test.repo"
    ),
    desc_path
  )

  before <- getOption("repos")
  repos <- load_intent_repos(tmp_dir)
  after <- getOption("repos")

  expect_equal(repos[["TEST"]], "https://test.repo")
  expect_equal(before, after)
})

test_that("extract_pkg_name strips user/repo and @version", {
  expect_equal(extract_pkg_name("dplyr"), "dplyr")
  expect_equal(extract_pkg_name("user/dplyr"), "dplyr")
  expect_equal(extract_pkg_name("dplyr@1.0.0"), "dplyr")
  expect_equal(extract_pkg_name("user/dplyr@0.1.0"), "dplyr")
  expect_equal(extract_pkg_name("tidyverse/dplyr@1.1.4"), "dplyr")
})

test_that("intent_get_project_deps reads DESCRIPTION dependencies", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  writeLines(
    c(
      "Package: testpkg",
      "Imports:",
      "    dplyr,",
      "    glue",
      "Suggests:",
      "    testthat"
    ),
    file.path(tmp_dir, "DESCRIPTION")
  )

  deps <- intent_get_project_deps(tmp_dir)
  expect_true("dplyr" %in% deps$package)
  expect_true("glue" %in% deps$package)
  expect_true("testthat" %in% deps$package)
})

test_that("intent_sync_project calls backend snapshot and restore", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  writeLines(
    c(
      "Package: testpkg",
      "Config/intent/repos/CRAN: https://example.com"
    ),
    file.path(tmp_dir, "DESCRIPTION")
  )

  snap_called <- NULL
  rest_called <- NULL

  mockery::stub(intent_sync_project, "intent_snapshot", function(project) {
    snap_called <<- list(project = project)
  })
  mockery::stub(
    intent_sync_project,
    "backend_restore",
    function(project, repos) {
      rest_called <<- list(project = project, repos = repos)
    }
  )

  intent_sync_project(tmp_dir)

  expect_equal(snap_called$project, tmp_dir)
  expect_equal(rest_called$project, tmp_dir)
  expect_equal(rest_called$repos[["CRAN"]], "https://example.com")
})

test_that("intent_snapshot does not replace lockfile on source policy error", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  writeLines(
    c(
      "Package: testpkg",
      "Config/intent/repos/CRAN: https://example.com",
      "Config/intent/source-policy/mode: error"
    ),
    file.path(tmp_dir, "DESCRIPTION")
  )
  lockfile <- file.path(tmp_dir, "renv.lock")
  writeLines("official lockfile", lockfile)

  mockery::stub(
    intent_snapshot,
    "backend_snapshot",
    function(project, repos, force, lockfile) {
      writeLines("candidate lockfile", lockfile)
    }
  )
  mockery::stub(intent_snapshot, "renv::lockfile_read", function(file) {
    list(
      Packages = list(
        glue = list(
          Version = "1.0.0",
          Source = "Repository",
          Repository = "RSPM"
        )
      )
    )
  })

  expect_error(
    intent_snapshot(tmp_dir),
    "official renv.lock was not updated"
  )
  expect_equal(readLines(lockfile), "official lockfile")
})

test_that("repo_url_is_platform_specific detects Linux-specific PPM URLs", {
  expect_true(repo_url_is_platform_specific(
    "https://packagemanager.posit.co/cran/__linux__/manylinux_2_28/latest"
  ))
})

test_that("repo_url_is_platform_specific detects macOS-specific PPM URLs", {
  expect_true(repo_url_is_platform_specific(
    "https://packagemanager.posit.co/cran/__macos__/latest"
  ))
})

test_that("repo_url_is_platform_specific detects Windows-specific PPM URLs", {
  expect_true(repo_url_is_platform_specific(
    "https://packagemanager.posit.co/cran/__windows__/latest"
  ))
})

test_that("repo_url_is_platform_specific returns FALSE for platform-agnostic URLs", {
  expect_false(repo_url_is_platform_specific(
    "https://packagemanager.posit.co/cran/latest"
  ))
  expect_false(repo_url_is_platform_specific(
    "https://cran.r-project.org"
  ))
})

test_that("repo_url_is_platform_specific detects manylinux in URL", {
  expect_true(repo_url_is_platform_specific(
    "https://example.com/r/src/contrib/manylinux/latest"
  ))
})

test_that("intent_check_platform_repos returns empty when mode is off", {
  repos <- c(
    CRAN = "https://packagemanager.posit.co/cran/__linux__/manylinux/latest"
  )
  issues <- intent_check_platform_repos(repos, list(mode = "off"))
  expect_equal(nrow(issues), 0)
})

test_that("intent_check_platform_repos returns warning in warn mode", {
  repos <- c(
    CRAN = "https://packagemanager.posit.co/cran/__linux__/manylinux/latest"
  )
  issues <- intent_check_platform_repos(repos, list(mode = "warn"))
  expect_equal(nrow(issues), 1)
  expect_equal(issues$severity[[1]], "warning")
  expect_match(issues$message[[1]], "platform-specific")
})

test_that("intent_check_platform_repos returns error in error mode", {
  repos <- c(
    CRAN = "https://packagemanager.posit.co/cran/__linux__/manylinux/latest"
  )
  issues <- intent_check_platform_repos(repos, list(mode = "error"))
  expect_equal(nrow(issues), 1)
  expect_equal(issues$severity[[1]], "error")
})

test_that("intent_check_platform_repos returns empty for platform-agnostic URL", {
  repos <- c(CRAN = "https://packagemanager.posit.co/cran/latest")
  issues <- intent_check_platform_repos(repos, list(mode = "warn"))
  expect_equal(nrow(issues), 0)
})
