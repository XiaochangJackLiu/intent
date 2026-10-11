# Dependency-free command-boundary checks. Run from the repository root.
# This complements, but does not replace, testthat/package/backend tests.
fixture <- new.env(parent = globalenv())
for (path in list.files("R", pattern = "[.]R$", full.names = TRUE)) {
  sys.source(path, fixture)
}

local(
  {
    checks <- 0L
    check <- function(ok) {
      stopifnot(isTRUE(ok))
      checks <<- checks + 1L
    }
    calls <- list()
    for (command in c(
      "init",
      "add",
      "remove",
      "sync",
      "status",
      "verify",
      "adopt"
    )) {
      stub <- local({
        verb <- command
        function(...) {
          calls[[length(calls) + 1L]] <<- list(verb = verb, args = list(...))
          new_intent_plan("fixture", verb, "would_change_fixture")
        }
      })
      assign(paste0("cmd_", command), stub)
    }

    rejects <- list(
      c("adopt", "--apply", "--dry-run"),
      c("adopt", "--dry-run", "--apply"),
      c("sync", "--json"),
      c("add", "pkg", "--json"),
      c("remove", "pkg", "--dev"),
      c("status", "--dry-run"),
      c("verify", "--no-prune"),
      c("doctor", "--dev"),
      c("init", "--apply"),
      c("init", "--dry-run"),
      c("adopt", "--no-default-repo"),
      c("adopt", "--apply", "--project", "--dry-run"),
      c("adopt", "--repo", "--apply", "--dry-run"),
      c("adopt", "--strategy", "--apply", "--dry-run")
    )
    for (args in rejects) {
      before <- length(calls)
      err <- tryCatch(intent_cli(args), error = identity)
      check(inherits(err, "error"))
      check(length(calls) == before)
    }

    for (command in c("add", "remove", "sync")) {
      args <- c(command, if (command != "sync") "pkg", "--dry-run")
      before <- length(calls)
      output <- capture.output(result <- withVisible(intent_cli(args)))
      check(any(grepl("would_change_fixture", output, fixed = TRUE)))
      check(!result$visible)
      check(inherits(result$value, "intent_plan"))
      check(length(calls) == before + 1L)
      check(isTRUE(calls[[length(calls)]]$args$dry_run))
    }

    for (args in list(character(), "--dry-run", "--yes", "--apply")) {
      invisible(capture.output(intent_cli(c("adopt", args))))
      check(identical(
        calls[[length(calls)]]$args$dry_run,
        !"--apply" %in% args
      ))
    }

    invisible(capture.output(intent_cli(c(
      "add",
      "pkg",
      "--dev",
      "--project",
      "target"
    ))))
    check(isTRUE(calls[[length(calls)]]$args$dev))
    check(identical(calls[[length(calls)]]$args$project, "target"))

    invisible(capture.output(intent_cli(c("sync", "--no-prune", "--prune"))))
    check(isTRUE(calls[[length(calls)]]$args$prune))
    invisible(capture.output(intent_cli(c("sync", "--prune", "--no-prune"))))
    check(identical(calls[[length(calls)]]$args$prune, FALSE))

    invisible(capture.output(intent_cli(c(
      "init",
      "target",
      "--repo",
      "A=https://a.test",
      "--repo",
      "B=https://b.test",
      "--yes"
    ))))
    check(identical(
      calls[[length(calls)]]$args$repos,
      c(A = "https://a.test", B = "https://b.test")
    ))

    # Actual JSON serialization requires jsonlite. When unavailable, test the
    # CLI rendering boundary with an exact serializer stub, not a fake JSON parser.
    if (requireNamespace("jsonlite", quietly = TRUE)) {
      output <- capture.output(intent_cli(c("sync", "--dry-run", "--json")))
      decoded <- jsonlite::fromJSON(paste(output, collapse = "\n"))
      check(identical(decoded$command, "sync"))
      cat("JSON serialization checked with jsonlite.\n")
    } else {
      as.character.intent_plan <- function(x, ...) '{"command":"sync"}'
      output <- capture.output(intent_cli(c("sync", "--dry-run", "--json")))
      check(identical(output, '{"command":"sync"}'))
      cat(
        "JSON rendering boundary checked with serializer stub; jsonlite unavailable.\n"
      )
    }
    cat("Passed", checks, "offline CLI boundary assertions.\n")
  },
  envir = fixture
)
