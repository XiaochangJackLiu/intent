bootstrap_packages <- function() {
  c("intent", "pak", "renv")
}

bootstrap_dependency_plan <- function(
  rproject,
  versions = bootstrap_dependency_versions(),
  override = FALSE
) {
  bootstrap_validate_versions(versions)

  deps <- rproject$get_deps()
  add <- bootstrap_dependency_rows_empty()
  preserve <- bootstrap_dependency_rows_empty()
  issues <- bootstrap_dependency_issues_empty()

  for (pkg in bootstrap_packages()) {
    existing <- deps[deps$package == pkg, , drop = FALSE]
    default_version <- bootstrap_version_or_any(versions[[pkg]])

    if (nrow(existing) == 0) {
      add <- rbind(
        add,
        bootstrap_dependency_row(pkg, "Suggests", default_version)
      )
      next
    }

    if (
      isTRUE(override) &&
        !identical(existing$version[[1]], default_version)
    ) {
      add <- rbind(
        add,
        bootstrap_dependency_row(pkg, "Suggests", default_version)
      )
      issues <- rbind(
        issues,
        bootstrap_dependency_issue(
          pkg,
          "info",
          sprintf(
            "%s constraint '%s' overrides existing declaration '%s'",
            pkg,
            default_version,
            existing$version[[1]]
          )
        )
      )
      next
    }

    preserved <- bootstrap_dependency_row(
      pkg,
      existing$type[[1]],
      existing$version[[1]]
    )
    preserve <- rbind(preserve, preserved)

    issue <- bootstrap_dependency_conflict(
      pkg,
      existing$version[[1]],
      versions[[pkg]]
    )
    if (!is.null(issue)) {
      issues <- rbind(issues, issue)
    }
  }

  structure(
    list(
      add = add,
      preserve = preserve,
      issues = issues,
      ok = !any(issues$severity == "error")
    ),
    class = "bootstrap_dependency_plan"
  )
}

bootstrap_validate_versions <- function(versions) {
  intent_version <- versions[["intent"]]
  if (
    is.null(intent_version) ||
      is.na(intent_version) ||
      !nzchar(intent_version) ||
      identical(intent_version, "*")
  ) {
    return(invisible(TRUE))
  }
  if (bootstrap_is_lower_bound(intent_version)) {
    return(invisible(TRUE))
  }
  stop(
    "intent version must be a '>=' constraint, got '",
    intent_version,
    "'.",
    call. = FALSE
  )
}

apply_bootstrap_dependencies <- function(rproject, plan) {
  if (!isTRUE(plan$ok)) {
    stop(
      "Bootstrap dependency plan has blocking issues:\n",
      paste(sprintf("- %s", plan$issues$message), collapse = "\n"),
      call. = FALSE
    )
  }

  for (i in seq_len(nrow(plan$add))) {
    rproject$set_dep(
      plan$add$package[[i]],
      type = plan$add$type[[i]],
      version = plan$add$version[[i]]
    )
  }

  invisible(rproject)
}

bootstrap_dependency_rows_empty <- function() {
  data.frame(
    package = character(),
    type = character(),
    version = character(),
    stringsAsFactors = FALSE
  )
}

bootstrap_dependency_row <- function(package, type, version) {
  data.frame(
    package = package,
    type = type,
    version = bootstrap_version_or_any(version),
    stringsAsFactors = FALSE
  )
}

bootstrap_dependency_issues_empty <- function() {
  data.frame(
    package = character(),
    severity = character(),
    message = character(),
    stringsAsFactors = FALSE
  )
}

bootstrap_dependency_issue <- function(package, severity, message) {
  data.frame(
    package = package,
    severity = severity,
    message = message,
    stringsAsFactors = FALSE
  )
}

bootstrap_dependency_conflict <- function(
  package,
  user_version,
  required_version
) {
  if (!package %in% c("pak", "renv")) {
    return(NULL)
  }
  if (!bootstrap_is_lower_bound(required_version)) {
    return(NULL)
  }

  required <- bootstrap_parse_version_constraint(required_version)
  if (is.null(required)) {
    return(NULL)
  }

  user <- bootstrap_parse_version_constraint(user_version)
  if (is.null(user)) {
    if (
      !is.null(user_version) &&
        !is.na(user_version) &&
        nzchar(user_version) &&
        !identical(user_version, "*")
    ) {
      return(bootstrap_dependency_issue(
        package,
        "warning",
        sprintf(
          "%s constraint '%s' could not be parsed; preserving as-is",
          package,
          user_version
        )
      ))
    }
    return(NULL)
  }

  # Warning: user lower bound is looser than intent's requirement
  if (
    identical(user$operator, ">=") &&
      identical(required$operator, ">=")
  ) {
    if (utils::compareVersion(user$version, required$version) < 0) {
      return(bootstrap_dependency_issue(
        package,
        "warning",
        sprintf(
          "%s constraint '%s' is looser than intent requirement '%s'",
          package,
          user_version,
          required_version
        )
      ))
    }
  }

  # Info: user strict lower bound with intent non-strict requirement
  if (
    identical(user$operator, ">") &&
      identical(required$operator, ">=")
  ) {
    return(bootstrap_dependency_issue(
      package,
      "info",
      sprintf(
        "%s constraint '%s' uses strict lower bound; intent requirement is '%s'",
        package,
        user_version,
        required_version
      )
    ))
  }

  conflicts <- FALSE
  if (identical(user$operator, "==")) {
    conflicts <- utils::compareVersion(user$version, required$version) < 0
  } else if (identical(user$operator, "<")) {
    conflicts <- utils::compareVersion(user$version, required$version) <= 0
  } else if (identical(user$operator, "<=")) {
    conflicts <- utils::compareVersion(user$version, required$version) < 0
  }

  if (!conflicts) {
    return(NULL)
  }

  bootstrap_dependency_issue(
    package,
    "error",
    sprintf(
      "%s constraint '%s' conflicts with intent requirement '%s'",
      package,
      user_version,
      required_version
    )
  )
}

bootstrap_parse_version_constraint <- function(version) {
  if (
    is.null(version) ||
      is.na(version) ||
      !nzchar(version) ||
      identical(version, "*")
  ) {
    return(NULL)
  }

  match <- regexec("^\\s*(>=|<=|==|>|<)\\s*([0-9][^[:space:]]*)\\s*$", version)
  parts <- regmatches(version, match)[[1]]
  if (length(parts) != 3) {
    return(NULL)
  }

  list(operator = parts[[2]], version = parts[[3]])
}

bootstrap_is_lower_bound <- function(version) {
  parsed <- bootstrap_parse_version_constraint(version)
  !is.null(parsed) && identical(parsed$operator, ">=")
}

bootstrap_version_or_any <- function(version) {
  if (is.null(version) || is.na(version) || !nzchar(version)) {
    return("*")
  }
  version
}

bootstrap_dependency_versions <- function(
  metadata = utils::packageDescription("intent"),
  intent_version = bootstrap_intent_version(metadata)
) {
  c(
    intent = paste(">=", intent_version),
    pak = bootstrap_dependency_lower_bound("pak", metadata),
    renv = bootstrap_dependency_lower_bound("renv", metadata)
  )
}

bootstrap_intent_version <- function(
  metadata = utils::packageDescription("intent")
) {
  version <- tryCatch(
    as.character(utils::packageVersion("intent")),
    error = function(e) NA_character_
  )
  if (!is.na(version) && nzchar(version)) {
    return(version)
  }

  version <- metadata[["Version"]]
  if (!is.null(version) && !is.na(version) && nzchar(version)) {
    return(version)
  }

  "0.0.0"
}

bootstrap_dependency_lower_bound <- function(
  package,
  metadata = utils::packageDescription("intent")
) {
  deps <- bootstrap_metadata_deps(metadata)
  match <- deps[deps$package == package, , drop = FALSE]
  if (nrow(match) == 0) {
    return(NA_character_)
  }

  version <- match$version[[1]]
  if (bootstrap_is_lower_bound(version)) {
    return(version)
  }

  NA_character_
}

bootstrap_metadata_deps <- function(metadata) {
  fields <- c("Depends", "Imports", "Suggests")
  values <- vapply(
    fields,
    function(field) {
      value <- metadata[[field]]
      if (is.null(value) || is.na(value)) {
        ""
      } else {
        value
      }
    },
    character(1)
  )
  values <- values[nzchar(values)]
  if (length(values) == 0) {
    return(data.frame(
      type = character(),
      package = character(),
      version = character(),
      stringsAsFactors = FALSE
    ))
  }

  path <- tempfile("intent-bootstrap-", fileext = ".DESCRIPTION")
  on.exit(unlink(path), add = TRUE)
  lines <- c(
    "Package: intent-bootstrap",
    "Title: Internal Bootstrap Metadata Parser",
    "Version: 0.0.0",
    unlist(
      Map(format_dcf_field, names(values), values),
      use.names = FALSE
    )
  )
  writeLines(lines, path)
  desc::desc_get_deps(file = path)
}

format_dcf_field <- function(field, value) {
  value_lines <- strsplit(value, "\n", fixed = TRUE)[[1]]
  value_lines <- value_lines[nzchar(trimws(value_lines))]
  first <- sprintf("%s: %s", field, value_lines[[1]])
  if (length(value_lines) == 1) {
    return(first)
  }
  c(first, paste0("    ", value_lines[-1]))
}
