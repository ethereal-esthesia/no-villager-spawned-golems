#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

sed -n 's/^paperApiVersion=//p' "$ROOT_DIR/gradle.properties" | head -n 1
