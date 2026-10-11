test_that("intent::sync restores environment from lockfile", {
  # Setup
  tmp_dir <- file.path(
    Sys.getenv("R_USER_CACHE_DIR", unset = tempdir()),
    paste0("intent_test_sync_", Sys.getpid())
  )
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  old_dir <- getwd()
  on.exit(
    {
      setwd(old_dir)
      unlink(tmp_dir, recursive = TRUE)
    },
    add = TRUE,
    after = FALSE
  )

  # Initialize
  pkg_to_test <- "dplyr"
  suppressMessages(init(
    path = tmp_dir,
    repos = c(CRAN = "https://packagemanager.posit.co/cran/latest")
  ))

  # delete `intent` from dependencies as unavailable on CRAN
  desc::desc_del_dep(
    "intent",
    file = file.path(tmp_dir, "DESCRIPTION")
  )

  # add new dependency to DESCRIPTION
  desc::desc_set_dep(
    pkg_to_test,
    type = "Imports",
    file = file.path(tmp_dir, "DESCRIPTION")
  )

  lib_path <- callr::r(
    function(old_dir, tmp_dir) {
      if (!requireNamespace("intent", quietly = TRUE)) {
        pkgload::load_all(old_dir)
      }

      # Set repos in current session since .Rprofile is not loaded
      setwd(tmp_dir)
      Sys.setenv(RENV_CONFIG_PAK_ENABLED = TRUE)
      Sys.setenv(RENV_CONFIG_SANDBOX_ENABLED = TRUE)
      renv::load(project = tmp_dir, quiet = TRUE)
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/latest"))

      intent::sync()

      # Check Library
      # renv library path
      renv::paths$library()
    },
    args = list(
      old_dir = old_dir,
      tmp_dir = tmp_dir
    )
  )

  # Check Project Library
  expect_true(dir.exists(file.path(lib_path, pkg_to_test)))

  # Check Lockfile
  lock <- renv::lockfile_read(file.path(tmp_dir, "renv.lock"))
  expect_true(pkg_to_test %in% names(lock$Packages))
})
