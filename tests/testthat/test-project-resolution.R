test_that("resolve_project uses explicit project paths", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  writeLines("Package: testpkg", file.path(tmp_dir, "DESCRIPTION"))

  expect_equal(resolve_project(tmp_dir), normalize_project_path(tmp_dir))
})

test_that("resolve_project discovers current or parent projects", {
  tmp_dir <- tempfile()
  nested_dir <- file.path(tmp_dir, "child", "grandchild")
  dir.create(nested_dir, recursive = TRUE)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  writeLines("Package: testpkg", file.path(tmp_dir, "DESCRIPTION"))

  withr::with_dir(nested_dir, {
    expect_equal(resolve_project(), normalize_project_path(tmp_dir))
  })
})

test_that("resolve_project errors clearly when no project exists", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  mockery::stub(resolve_project, "renv::project", function(...) NULL)

  withr::with_dir(tmp_dir, {
    expect_error(
      resolve_project(),
      "No intent project found"
    )
  })
})

test_that("sync honors explicit project before active renv state", {
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
  writeLines(
    "{}",
    file.path(tmp_dir, "renv.lock")
  )

  restored_project <- NULL
  mockery::stub(cmd_sync, "intent_reconcile", function(project, ...) {
    restored_project <<- project
  })
  cmd_sync(project = tmp_dir)

  expect_equal(restored_project, normalize_project_path(tmp_dir))
})
