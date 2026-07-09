test_that("bootstrap plan adds missing tool dependencies", {
  rproject <- desc::description$new("!new")
  rproject$set("Package", "demo")

  plan <- bootstrap_dependency_plan(
    rproject,
    versions = c(intent = ">= 1.2.3", pak = ">= 0.9.0", renv = NA)
  )

  expect_true(plan$ok)
  expect_equal(plan$add$package, c("intent", "pak", "renv"))
  expect_equal(plan$add$type, rep("Suggests", 3))
  expect_equal(plan$add$version, c(">= 1.2.3", ">= 0.9.0", "*"))
  expect_equal(nrow(plan$preserve), 0)
  expect_equal(nrow(plan$issues), 0)
})

test_that("bootstrap plan preserves existing tool constraints", {
  rproject <- desc::description$new("!new")
  rproject$set("Package", "demo")
  rproject$set_dep("intent", type = "Suggests", version = ">= 0.9.0")
  rproject$set_dep("pak", type = "Suggests", version = ">= 0.8.0")
  rproject$set_dep("renv", type = "Suggests", version = "== 1.1.4")

  plan <- bootstrap_dependency_plan(
    rproject,
    versions = c(intent = ">= 1.2.3", pak = ">= 0.9.0", renv = ">= 1.1.0")
  )

  expect_true(plan$ok)
  expect_equal(nrow(plan$add), 0)
  expect_equal(plan$preserve$package, c("intent", "pak", "renv"))
  expect_equal(plan$preserve$version, c(">= 0.9.0", ">= 0.8.0", "== 1.1.4"))
})

test_that("bootstrap dependency versions derive lower bounds from intent metadata", {
  versions <- bootstrap_dependency_versions(
    metadata = list(
      Version = "1.2.3",
      Imports = "pak (>= 0.9.0),\nrenv (>= 1.1.0)"
    ),
    intent_version = "1.2.3"
  )

  expect_equal(versions[["intent"]], ">= 1.2.3")
  expect_equal(versions[["pak"]], ">= 0.9.0")
  expect_equal(versions[["renv"]], ">= 1.1.0")
})

test_that("bootstrap dependency versions do not copy non-lower-bound defaults", {
  versions <- bootstrap_dependency_versions(
    metadata = list(
      Version = "1.2.3",
      Imports = "pak (== 0.9.0),\nrenv (< 2.0.0)"
    ),
    intent_version = "1.2.3"
  )

  expect_equal(versions[["intent"]], ">= 1.2.3")
  expect_true(is.na(versions[["pak"]]))
  expect_true(is.na(versions[["renv"]]))
})

test_that("bootstrap plan allows satisfying user lower bounds", {
  rproject <- desc::description$new("!new")
  rproject$set("Package", "demo")
  rproject$set_dep("pak", type = "Suggests", version = ">= 1.0.0")
  rproject$set_dep("renv", type = "Suggests", version = ">= 1.1.0")

  plan <- bootstrap_dependency_plan(
    rproject,
    versions = c(intent = ">= 1.2.3", pak = ">= 0.9.0", renv = ">= 1.1.0")
  )

  expect_true(plan$ok)
  expect_equal(nrow(plan$issues), 0)
})

test_that("bootstrap plan detects exact pins below required lower bounds", {
  rproject <- desc::description$new("!new")
  rproject$set("Package", "demo")
  rproject$set_dep("pak", type = "Suggests", version = "== 0.8.0")

  plan <- bootstrap_dependency_plan(
    rproject,
    versions = c(intent = ">= 1.2.3", pak = ">= 0.9.0", renv = NA)
  )

  expect_false(plan$ok)
  expect_equal(plan$issues$package, "pak")
  expect_match(plan$issues$message, "conflicts")
})

test_that("bootstrap plan detects upper bounds below required lower bounds", {
  rproject <- desc::description$new("!new")
  rproject$set("Package", "demo")
  rproject$set_dep("renv", type = "Suggests", version = "< 1.1.0")

  plan <- bootstrap_dependency_plan(
    rproject,
    versions = c(intent = ">= 1.2.3", pak = NA, renv = ">= 1.1.0")
  )

  expect_false(plan$ok)
  expect_equal(plan$issues$package, "renv")
  expect_match(plan$issues$message, "conflicts")
})

test_that("apply bootstrap dependencies mutates only from add plan entries", {
  rproject <- desc::description$new("!new")
  rproject$set("Package", "demo")
  rproject$set_dep("renv", type = "Suggests", version = "== 1.1.4")

  plan <- bootstrap_dependency_plan(
    rproject,
    versions = c(intent = ">= 1.2.3", pak = NA, renv = ">= 1.1.0")
  )
  apply_bootstrap_dependencies(rproject, plan)

  deps <- rproject$get_deps()
  expect_equal(deps$version[deps$package == "intent"], ">= 1.2.3")
  expect_equal(deps$version[deps$package == "pak"], "*")
  expect_equal(deps$version[deps$package == "renv"], "== 1.1.4")
})

test_that("apply bootstrap dependencies refuses blocking issues", {
  rproject <- desc::description$new("!new")
  rproject$set("Package", "demo")
  rproject$set_dep("renv", type = "Suggests", version = "< 1.1.0")

  plan <- bootstrap_dependency_plan(
    rproject,
    versions = c(intent = ">= 1.2.3", pak = NA, renv = ">= 1.1.0")
  )

  expect_error(
    apply_bootstrap_dependencies(rproject, plan),
    "blocking issues"
  )
})
