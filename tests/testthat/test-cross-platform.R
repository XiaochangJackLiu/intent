test_that("fixture: platform-agnostic lockfile repos resolve correctly", {
  lockfile <- file.path("fixtures", "lockfile-platform-agnostic.json")
  lock <- renv::lockfile_read(lockfile)

  repos <- c(CRAN = "https://packagemanager.posit.co/cran/latest")
  lock <- intent_supplement_repositories(lock, repos)

  expect_true("CRAN" %in% names(lock$R$Repositories))
})

test_that("fixture: RSPM name is supplemented when URL matches declared repo", {
  lockfile <- file.path("fixtures", "lockfile-rspm-name.json")
  lock <- renv::lockfile_read(lockfile)

  # Declare CRAN with the same URL — RSPM should be resolved
  repos <- c(CRAN = "https://packagemanager.posit.co/cran/latest")
  lock <- intent_supplement_repositories(lock, repos)

  # RSPM should be in the repo table after supplementation
  expect_true("RSPM" %in% names(lock$R$Repositories))
})

test_that("fixture: verify passes on platform-agnostic lockfile", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  # Copy fixture lockfile to project
  file.copy(
    file.path("fixtures", "lockfile-platform-agnostic.json"),
    file.path(tmp_dir, "renv.lock")
  )

  writeLines(
    c(
      "Package: testpkg",
      "Version: 0.0.1",
      "Imports: glue",
      "Config/intent/repos/CRAN: https://packagemanager.posit.co/cran/latest"
    ),
    file.path(tmp_dir, "DESCRIPTION")
  )

  status <- cmd_status(project = tmp_dir)
  result <- cmd_verify(project = tmp_dir)

  # Should have no platform_repos issues
  platform_issues <- result$issues[
    result$issues$check == "platform_repos",
    ,
    drop = FALSE
  ]
  expect_equal(nrow(platform_issues), 0)
})

test_that("intent_supplement_repositories resolves RSPM via URL matching with fixture", {
  lockfile <- file.path("fixtures", "lockfile-rspm-name.json")
  lock <- renv::lockfile_read(lockfile)

  # Declare CRAN with same URL but different name
  repos <- c(CRAN = "https://packagemanager.posit.co/cran/latest")
  supplemented <- intent_supplement_repositories(lock, repos)

  # After supplementation, RSPM should map to the CRAN URL
  expect_equal(
    supplemented$R$Repositories[["RSPM"]],
    "https://packagemanager.posit.co/cran/latest"
  )
})
