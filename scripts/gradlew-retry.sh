#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAX_ATTEMPTS=3
attempt=1
output_file="$(mktemp)"
trap 'rm -f "$output_file"' EXIT

while true; do
  if "$ROOT_DIR/gradlew" "$@" >"$output_file" 2>&1; then
    cat "$output_file"
    exit 0
  else
    status=$?
  fi

  cat "$output_file" >&2
  if [ "$attempt" -ge "$MAX_ATTEMPTS" ] ||
    ! grep -Eq 'Server returned HTTP response code: 5[0-9]{2} for URL: https://services\.gradle\.org/distributions/' "$output_file"; then
    exit "$status"
  fi

  delay=$((attempt * 5))
  echo "Gradle distribution server returned a 5xx response; retrying in ${delay}s (attempt $((attempt + 1))/$MAX_ATTEMPTS)." >&2
  sleep "$delay"
  attempt=$((attempt + 1))
done
