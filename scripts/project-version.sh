#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT_DIR/gradlew" -q -p "$ROOT_DIR" properties \
  | awk -F': ' '$1 == "version" { print $2; found = 1 } END { exit found ? 0 : 1 }'
