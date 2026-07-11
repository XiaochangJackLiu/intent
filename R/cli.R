intent_cli <- function(args = commandArgs(trailingOnly = TRUE)) {
  invisible(cli_main(args))
}

cli_main <- function(args) {
  if (length(args) == 0 || args[1] %in% c("-h", "--help")) {
    cli_print_help()
    return(invisible(NULL))
  }

  command <- args[1]
  command_args <- args[-1]

  switch(
    command,
    init = cli_init(command_args),
    add = cli_add(command_args),
    remove = cli_remove(command_args),
    sync = cli_sync(command_args),
    status = cli_status(command_args),
    verify = cli_verify(command_args),
    doctor = cli_verify(command_args),
    adopt = cli_adopt(command_args),
    stop("Unknown command: ", command, call. = FALSE)
  )
}

cli_init <- function(args) {
  parsed <- cli_collect_repos(args)
  path <- "."
  if (length(parsed$args) > 1) {
    stop("`intent init` accepts at most one path argument.", call. = FALSE)
  }
  if (length(parsed$args) == 1) {
    path <- parsed$args
  }

  cmd_init(
    path = path,
    repos = parsed$repos,
    confirm_repos = !parsed$yes && interactive(),
    use_default_repo = !parsed$no_default_repo
  )
}

cli_add <- function(args) {
  parsed <- cli_parse_common(args)
  dev <- parsed$flags[["dev"]]
  pkgs <- parsed$args
  if (length(pkgs) == 0) {
    stop("No packages specified.", call. = FALSE)
  }

  cmd_add(
    pkgs = pkgs,
    dev = dev,
    project = parsed$project,
    dry_run = parsed$dry_run
  )
}

cli_remove <- function(args) {
  parsed <- cli_parse_common(args)
  pkgs <- parsed$args
  if (length(pkgs) == 0) {
    stop("No packages specified.", call. = FALSE)
  }

  cmd_remove(
    pkgs = pkgs,
    project = parsed$project,
    dry_run = parsed$dry_run
  )
}

cli_sync <- function(args) {
  parsed <- cli_parse_common(args)
  if (length(parsed$args) > 0) {
    stop("`intent sync` does not accept package arguments.", call. = FALSE)
  }

  prune <- !identical(parsed$flags[["no_prune"]], TRUE)
  result <- cmd_sync(
    project = parsed$project,
    dry_run = parsed$dry_run,
    prune = prune
  )
  if (parsed$json && parsed$dry_run) {
    cat(as.character(result), "\n", sep = "")
  }
  invisible(result)
}

cli_status <- function(args) {
  parsed <- cli_parse_common(args)
  if (length(parsed$args) > 0) {
    stop("`intent status` does not accept package arguments.", call. = FALSE)
  }

  result <- cmd_status(project = parsed$project)
  if (parsed$json) {
    cat(as.character(result), "\n", sep = "")
  } else {
    print(result)
  }
  invisible(result)
}

cli_verify <- function(args) {
  parsed <- cli_parse_common(args)
  if (length(parsed$args) > 0) {
    stop("`intent verify` does not accept package arguments.", call. = FALSE)
  }

  result <- cmd_verify(project = parsed$project)
  if (parsed$json) {
    cat(as.character(result), "\n", sep = "")
  } else {
    print(result)
  }
  if (!isTRUE(result$ok)) {
    stop("Project verification failed.", call. = FALSE)
  }
  invisible(result)
}

cli_adopt <- function(args) {
  parsed <- cli_parse_common(args)
  if (length(parsed$args) > 0) {
    stop("`intent adopt` does not accept positional arguments.", call. = FALSE)
  }

  result <- cmd_adopt(
    path = parsed$project %||% ".",
    dry_run = parsed$dry_run
  )

  if (parsed$json) {
    cat(as.character(result), "\n", sep = "")
  } else {
    print(result)
  }
  invisible(result)
}

cli_parse_common <- function(args) {
  project <- NULL
  dry_run <- FALSE
  json <- FALSE
  flags <- list(dev = FALSE)
  rest <- character()
  i <- 1

  while (i <= length(args)) {
    arg <- args[[i]]
    if (identical(arg, "--project")) {
      if (i == length(args)) {
        stop("Missing value for --project.", call. = FALSE)
      }
      project <- args[[i + 1]]
      i <- i + 2
    } else if (identical(arg, "--dry-run")) {
      dry_run <- TRUE
      i <- i + 1
    } else if (identical(arg, "--json")) {
      json <- TRUE
      i <- i + 1
    } else if (identical(arg, "--dev")) {
      flags$dev <- TRUE
      i <- i + 1
    } else if (identical(arg, "--prune")) {
      flags$no_prune <- FALSE
      i <- i + 1
    } else if (identical(arg, "--no-prune")) {
      flags$no_prune <- TRUE
      i <- i + 1
    } else if (startsWith(arg, "--")) {
      stop("Unknown option: ", arg, call. = FALSE)
    } else {
      rest <- c(rest, arg)
      i <- i + 1
    }
  }

  list(
    args = rest,
    project = project,
    dry_run = dry_run,
    json = json,
    flags = flags
  )
}

cli_collect_repos <- function(args) {
  repos <- character()
  rest <- character()
  yes <- FALSE
  no_default_repo <- FALSE
  i <- 1

  while (i <= length(args)) {
    arg <- args[[i]]
    if (identical(arg, "--repo")) {
      if (i == length(args)) {
        stop("Missing value for --repo.", call. = FALSE)
      }
      repo <- cli_parse_repo(args[[i + 1]])
      repos[names(repo)] <- repo
      i <- i + 2
    } else if (identical(arg, "--yes")) {
      yes <- TRUE
      i <- i + 1
    } else if (identical(arg, "--no-default-repo")) {
      no_default_repo <- TRUE
      i <- i + 1
    } else if (startsWith(arg, "--")) {
      stop("Unknown option: ", arg, call. = FALSE)
    } else {
      rest <- c(rest, arg)
      i <- i + 1
    }
  }

  list(
    args = rest,
    repos = if (length(repos) == 0) NULL else repos,
    yes = yes,
    no_default_repo = no_default_repo
  )
}

cli_parse_repo <- function(value) {
  parts <- strsplit(value, "=", fixed = TRUE)[[1]]
  if (length(parts) != 2 || any(parts == "")) {
    stop("--repo must use NAME=URL format.", call. = FALSE)
  }

  repo <- parts[[2]]
  names(repo) <- parts[[1]]
  repo
}

cli_print_help <- function() {
  cat(
    paste(
      "Usage:",
      "  intent init [path] [--repo NAME=URL] [--yes] [--no-default-repo]",
      "  intent add [--project path] [--dev] [--dry-run] <package>...",
      "  intent remove [--project path] [--dry-run] <package>...",
      "  intent sync [--project path] [--dry-run] [--json] [--no-prune]",
      "  intent status [--project path] [--json]",
      "  intent verify [--project path] [--json]",
      "  intent doctor [--project path] [--json]",
      "  intent adopt [--project path] [--dry-run] [--json]",
      sep = "\n"
    ),
    "\n"
  )
}
