#' Show Project Dependency Status
#'
#' Reports drift between the project manifest, lockfile, and local library
#' without changing project state.
#'
#' @param project Path to the project directory. Defaults to the current intent project.
#'
#' @return An `intent_status` object containing structured drift information.
#' @export
status <- function(project = NULL) {
  cmd_status(project = project)
}

#' Verify Project Contract
#'
#' Checks whether the project manifest, repository policy, lockfile, and local
#' library satisfy intent's project contract without changing project state.
#'
#' @param project Path to the project directory. Defaults to the current intent project.
#'
#' @return An `intent_verification` object containing `ok`, `issues`, and the
#'   underlying `intent_status`.
#' @export
verify <- function(project = NULL) {
  cmd_verify(project = project)
}

#' @rdname verify
#' @export
doctor <- function(project = NULL) {
  verify(project = project)
}

#' @export
print.intent_status <- function(x, ...) {
  cat("Project: ", x$project, "\n", sep = "")
  cat("Library: ", x$library_path, "\n", sep = "")
  cat("R version: ", x$r_version, sep = "")
  if (!is.null(x$r_constraint)) {
    cat(" (constraint: ", x$r_constraint, ")", sep = "")
  }
  if (!is.null(x$lockfile_r_version) && x$lockfile_r_version != x$r_version) {
    cat(" [lockfile: ", x$lockfile_r_version, "]", sep = "")
  }
  cat("\n\n")

  print_status_count("Manifest packages", x$manifest_packages)
  print_status_count("Locked packages", x$locked_packages)
  print_status_count("Missing from lockfile", x$missing_from_lockfile)
  print_status_count("Extra in lockfile", x$extra_in_lockfile)
  print_status_count("Missing from library", x$missing_from_library)
  print_source_violations(x$source_violations)

  invisible(x)
}

#' @export
print.intent_verification <- function(x, ...) {
  cat("Project: ", x$project, "\n", sep = "")
  cat("Verification: ", if (isTRUE(x$ok)) "OK" else "FAILED", "\n", sep = "")

  if (nrow(x$issues) == 0) {
    cat("Issues: 0\n")
  } else {
    cat("Issues: ", nrow(x$issues), "\n", sep = "")
    for (i in seq_len(nrow(x$issues))) {
      issue <- x$issues[i, , drop = FALSE]
      cat(
        "  - [",
        issue$severity,
        "] ",
        issue$check,
        ": ",
        issue$message,
        "\n",
        sep = ""
      )
    }
  }

  invisible(x)
}

#' @export
print.intent_plan <- function(x, ...) {
  cat("Project: ", x$project, "\n", sep = "")
  cat("Command: ", x$command, "\n", sep = "")

  if (length(x$packages) > 0) {
    cat("Packages: ", paste(x$packages, collapse = ", "), "\n", sep = "")
  }

  cat("\nPlanned actions:\n")
  if (length(x$actions) == 0) {
    cat("  none\n")
  } else {
    for (action in x$actions) {
      cat("  - ", action, "\n", sep = "")
    }
  }

  invisible(x)
}

print_status_count <- function(label, values) {
  cat(label, ": ", length(values), sep = "")
  if (length(values) > 0) {
    cat(" (", paste(values, collapse = ", "), ")", sep = "")
  }
  cat("\n")
}

print_source_violations <- function(violations) {
  if (is.null(violations) || nrow(violations) == 0) {
    cat("Source policy violations: 0\n")
    return(invisible(NULL))
  }

  cat("Source policy violations: ", nrow(violations), "\n", sep = "")
  for (i in seq_len(nrow(violations))) {
    violation <- violations[i, , drop = FALSE]
    cat(
      "  - ",
      violation$package,
      ": ",
      violation$reason,
      "\n",
      sep = ""
    )
  }

  invisible(NULL)
}

#' @export
as.character.intent_status <- function(x, ...) {
  jsonlite::toJSON(unclass(x), auto_unbox = TRUE, pretty = FALSE)
}

#' @export
as.character.intent_verification <- function(x, ...) {
  out <- unclass(x)
  out$status <- unclass(out$status)
  jsonlite::toJSON(out, auto_unbox = TRUE, pretty = FALSE)
}

#' @export
as.character.intent_plan <- function(x, ...) {
  jsonlite::toJSON(unclass(x), auto_unbox = TRUE, pretty = FALSE)
}

#' @export
print.bootstrap_dependency_plan <- function(x, ...) {
  if (nrow(x$add) > 0) {
    cat("Add:\n")
    for (i in seq_len(nrow(x$add))) {
      cat(sprintf(
        "  + %s (%s) [%s]\n",
        x$add$package[[i]],
        x$add$version[[i]],
        x$add$type[[i]]
      ))
    }
    cat("\n")
  }

  if (nrow(x$preserve) > 0) {
    cat("Preserve:\n")
    for (i in seq_len(nrow(x$preserve))) {
      cat(sprintf(
        "  = %s (%s) [%s]\n",
        x$preserve$package[[i]],
        x$preserve$version[[i]],
        x$preserve$type[[i]]
      ))
    }
    cat("\n")
  }

  if (nrow(x$issues) > 0) {
    cat("Issues:\n")
    for (i in seq_len(nrow(x$issues))) {
      marker <- if (identical(x$issues$severity[[i]], "error")) "!" else "?"
      cat(sprintf(
        "  %s [%s] %s: %s\n",
        marker,
        x$issues$severity[[i]],
        x$issues$package[[i]],
        x$issues$message[[i]]
      ))
    }
    cat("\n")
  }

  cat(sprintf("OK: %s\n", if (isTRUE(x$ok)) "TRUE" else "FALSE"))
  invisible(x)
}

#' @export
as.character.bootstrap_dependency_plan <- function(x, ...) {
  jsonlite::toJSON(unclass(x), auto_unbox = TRUE, pretty = FALSE)
}
