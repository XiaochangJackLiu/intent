#!/bin/sh
# Locate Rscript and run the roxygen2 check.
# Searches common R installation paths on Windows, macOS, and Linux.

find_rscript() {
  # Prefer the newest R installation on Windows
  for base in "/c/Program Files/R" "/c/progra~1/R" "C:/Program Files/R"; do
    if [ -d "$base" ]; then
      newest=$(ls -d "$base"/R-*/bin/Rscript.exe 2>/dev/null | sort -V | tail -1)
      if [ -n "$newest" ] && { [ -x "$newest" ] || [ -f "$newest" ]; }; then
        echo "$newest"
        return 0
      fi
    fi
  done

  # Try PATH
  if command -v Rscript >/dev/null 2>&1; then
    command -v Rscript
    return 0
  fi

  # macOS/Linux
  for r in /usr/local/bin/Rscript /usr/bin/Rscript; do
    if [ -x "$r" ]; then
      echo "$r"
      return 0
    fi
  done

  return 1
}

RSCRIPT=$(find_rscript)
if [ -z "$RSCRIPT" ]; then
  echo "WARNING: Rscript not found, skipping roxygen check" >&2
  exit 0
fi

exec "$RSCRIPT" tools/check-roxygen.R "$@"
