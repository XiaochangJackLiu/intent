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

test_that("print bootstrap plan shows add entries with markers", {
  rproject <- desc::description$new("!new")
  rproject$set("Package", "demo")

  plan <- bootstrap_dependency_plan(
    rproject,
    versions = c(intent = ">= 1.2.3", pak = ">= 0.9.0", renv = NA)
  )

  output <- capture.output(print(plan))
  text <- paste(output, collapse = "\n")

  expect_match(text, "Add:", fixed = TRUE)
  expect_match(text, "+ intent (>= 1.2.3) [Suggests]", fixed = TRUE)
  expect_match(text, "+ pak (>= 0.9.0) [Suggests]", fixed = TRUE)
  expect_match(text, "+ renv (*) [Suggests]", fixed = TRUE)
  expect_match(text, "OK: TRUE", fixed = TRUE)
})

test_that("print bootstrap plan shows preserve entries with markers", {
  rproject <- desc::description$new("!new")
  rproject$set("Package", "demo")
  rproject$set_dep("intent", type = "Suggests", version = ">= 0.9.0")
  rproject$set_dep("renv", type = "Suggests", version = "== 1.1.4")

  plan <- bootstrap_dependency_plan(
    rproject,
    versions = c(intent = ">= 1.2.3", pak = NA, renv = ">= 1.1.0")
  )

  output <- capture.output(print(plan))
  text <- paste(output, collapse = "\n")

  expect_match(text, "Preserve:", fixed = TRUE)
  expect_match(text, "= intent (>= 0.9.0) [Suggests]", fixed = TRUE)
  expect_match(text, "= renv (== 1.1.4) [Suggests]", fixed = TRUE)
})

test_that("print bootstrap plan shows issues with error and warning markers", {
  rproject <- desc::description$new("!new")
  rproject$set("Package", "demo")
  rproject$set_dep("renv", type = "Suggests", version = "< 1.1.0")

  plan <- bootstrap_dependency_plan(
    rproject,
    versions = c(intent = ">= 1.2.3", pak = NA, renv = ">= 1.1.0")
  )

  output <- capture.output(print(plan))
  text <- paste(output, collapse = "\n")

  expect_match(text, "Issues:", fixed = TRUE)
  expect_match(text, "! [error]", fixed = TRUE)
  expect_match(text, "OK: FALSE", fixed = TRUE)
})

test_that("print bootstrap plan shows OK when empty", {
  rproject <- desc::description$new("!new")
  rproject$set("Package", "demo")
  rproject$set_dep("intent", type = "Suggests", version = ">= 1.2.3")
  rproject$set_dep("pak", type = "Suggests", version = ">= 0.9.0")
  rproject$set_dep("renv", type = "Suggests", version = ">= 1.1.0")

  plan <- bootstrap_dependency_plan(
    rproject,
    versions = c(intent = ">= 1.2.3", pak = ">= 0.9.0", renv = ">= 1.1.0")
  )

  output <- capture.output(print(plan))
  text <- paste(output, collapse = "\n")

  expect_match(text, "OK: TRUE", fixed = TRUE)
  expect_false(grepl("Add:", text, fixed = TRUE))
  expect_false(grepl("Issues:", text, fixed = TRUE))
})

test_that("as.character.bootstrap_dependency_plan returns valid JSON", {
  rproject <- desc::description$new("!new")
  rproject$set("Package", "demo")

  plan <- bootstrap_dependency_plan(
    rproject,
    versions = c(intent = ">= 1.2.3", pak = ">= 0.9.0", renv = NA)
  )

  json_str <- as.character(plan)
  parsed <- jsonlite::fromJSON(json_str)

  expect_equal(parsed$add$package, c("intent", "pak", "renv"))
  expect_true(parsed$ok)
  expect_true(
    is.null(parsed$preserve) ||
      identical(parsed$preserve, list()) ||
      isTRUE(nrow(parsed$preserve) == 0)
  )
})

test_that("bootstrap plan warns on unparseable user constraint", {
  tmp <- tempfile(fileext = ".DESCRIPTION")
  writeLines(
    c(
      "Package: demo",
      "Version: 0.0.1",
      "Suggests:",
      "    renv (^1.0.0)"
    ),
    tmp
  )
  on.exit(unlink(tmp), add = TRUE)

  rproject <- suppressWarnings(desc::description$new(tmp))
  plan <- bootstrap_dependency_plan(
    rproject,
    versions = c(intent = ">= 1.2.3", pak = NA, renv = ">= 1.1.0")
  )

  expect_true(plan$ok)
  expect_true(nrow(plan$issues) > 0)
  expect_equal(plan$issues$severity[[1]], "warning")
  expect_match(plan$issues$message[[1]], "could not be parsed")
})

test_that("bootstrap plan warns on user >= looser than intent >=", {
  rproject <- desc::description$new("!new")
  rproject$set("Package", "demo")
  rproject$set_dep("pak", type = "Suggests", version = ">= 0.5.0")

  plan <- bootstrap_dependency_plan(
    rproject,
    versions = c(intent = ">= 1.2.3", pak = ">= 1.5.0", renv = NA)
  )

  expect_true(plan$ok)
  expect_true(nrow(plan$issues) > 0)
  expect_equal(plan$issues$severity[[1]], "warning")
  expect_match(plan$issues$message[[1]], "looser than")
})

test_that("bootstrap plan reports info on user > with intent >=", {
  rproject <- desc::description$new("!new")
  rproject$set("Package", "demo")
  rproject$set_dep("pak", type = "Suggests", version = "> 1.0.0")

  plan <- bootstrap_dependency_plan(
    rproject,
    versions = c(intent = ">= 1.2.3", pak = ">= 1.5.0", renv = NA)
  )

  expect_true(plan$ok)
  expect_true(nrow(plan$issues) > 0)
  expect_equal(plan$issues$severity[[1]], "info")
  expect_match(plan$issues$message[[1]], "strict lower bound")
})

test_that("bootstrap plan ok is FALSE only on error severity", {
  tmp <- tempfile(fileext = ".DESCRIPTION")
  writeLines(
    c(
      "Package: demo",
      "Version: 0.0.1",
      "Suggests:",
      "    pak (>= 0.5.0)"
    ),
    tmp
  )
  on.exit(unlink(tmp), add = TRUE)

  rproject <- desc::description$new(tmp)
  plan <- bootstrap_dependency_plan(
    rproject,
    versions = c(intent = ">= 1.2.3", pak = ">= 1.5.0", renv = NA)
  )

  # Only warnings, no errors → ok is still TRUE
  expect_true(plan$ok)
  expect_true(nrow(plan$issues) > 0)
  expect_false(any(plan$issues$severity == "error"))
  expect_true(any(plan$issues$severity == "warning"))

  # Add an error case
  rproject2 <- desc::description$new("!new")
  rproject2$set("Package", "demo")
  rproject2$set_dep("renv", type = "Suggests", version = "< 1.1.0")

  plan2 <- bootstrap_dependency_plan(
    rproject2,
    versions = c(intent = ">= 1.2.3", pak = NA, renv = ">= 1.1.0")
  )

  expect_false(plan2$ok)
  expect_true(any(plan2$issues$severity == "error"))
})
