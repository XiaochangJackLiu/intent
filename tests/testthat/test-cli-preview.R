test_that("adopt execution conflicts are rejected before dispatch", {
  mockery::stub(cli_adopt, "cmd_adopt", function(...) {
    stop("command must not be called")
  })
  for (args in list(
    c("--apply", "--dry-run"),
    c("--dry-run", "--apply")
  )) {
    expect_error(
      cli_adopt(args),
      "--apply and --dry-run cannot be used together"
    )
  }
})

test_that("adopt execution mode is explicit", {
  calls <- list()
  mockery::stub(cli_adopt, "cmd_adopt", function(...) {
    calls[[length(calls) + 1L]] <<- list(...)
    new_intent_plan("fixture", "adopt", "would_adopt")
  })
  for (args in list(character(), "--dry-run", "--yes", "--apply")) {
    invisible(capture.output(cli_adopt(args)))
  }
  expect_equal(
    vapply(calls, `[[`, logical(1), "dry_run"),
    c(TRUE, TRUE, TRUE, FALSE)
  )
  expect_false(calls[[3]]$confirm)
})

test_that("sync JSON requires preview before command dispatch", {
  mockery::stub(cli_sync, "cmd_sync", function(...) {
    stop("command must not be called")
  })
  expect_error(cli_sync("--json"), "--json requires --dry-run")
})

test_that("CLI entry point prints preview plans explicitly", {
  for (command in c("add", "remove", "sync")) {
    handler <- get(paste0("cli_", command))
    calls <- 0L
    mockery::stub(handler, paste0("cmd_", command), function(...) {
      calls <<- calls + 1L
      expect_true(list(...)$dry_run)
      new_intent_plan("fixture", command, "would_change_fixture")
    })
    main <- cli_main
    mockery::stub(main, paste0("cli_", command), handler)
    entry <- intent_cli
    mockery::stub(entry, "cli_main", main)
    args <- c(command, if (command != "sync") "pkg", "--dry-run")
    output <- capture.output(result <- withVisible(entry(args)))
    expect_match(paste(output, collapse = "\n"), "would_change_fixture")
    expect_false(result$visible)
    expect_s3_class(result$value, "intent_plan")
    expect_equal(calls, 1L)
  }
})

test_that("sync JSON preview has no human plan output", {
  mockery::stub(cli_sync, "cmd_sync", function(...) {
    new_intent_plan("fixture", "sync", "would_restore")
  })
  output <- capture.output(cli_sync(c("--dry-run", "--json")))
  decoded <- jsonlite::fromJSON(paste(output, collapse = "\n"))
  expect_equal(decoded$command, "sync")
  expect_equal(decoded$actions, "would_restore")
  expect_false(any(grepl("Planned actions:", output, fixed = TRUE)))
})

test_that("command-specific options fail before dispatch", {
  cases <- list(
    list("add", c("pkg", "--json")),
    list("remove", c("pkg", "--dev")),
    list("status", "--dry-run"),
    list("verify", "--no-prune"),
    list("doctor", "--dev"),
    list("init", "--apply"),
    list("init", "--dry-run"),
    list("adopt", "--no-default-repo")
  )
  for (case in cases) {
    command <- case[[1]]
    handler_name <- if (command == "doctor") "verify" else command
    handler <- get(paste0("cli_", handler_name))
    mockery::stub(handler, paste0("cmd_", handler_name), function(...) {
      stop("command must not be called")
    })
    expect_error(handler(case[[2]]), "does not support option")
  }
})

test_that("options cannot consume another option as their value", {
  expect_error(
    cli_parse_common(c("--project", "--dry-run")),
    "Missing value for --project"
  )
  for (option in c("--project", "--repo", "--strategy")) {
    expect_error(
      cli_collect_repos(c(option, "--apply", "--dry-run")),
      paste("Missing value for", option)
    )
  }
})
