#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROPERTIES_FILE="$ROOT_DIR/gradle.properties"
paper_version=""
paper_dependency_version=""
requested_plugin_version=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --paper-version)
      paper_version="${2:-}"
      shift 2
      ;;
    --paper-dependency-version)
      paper_dependency_version="${2:-}"
      shift 2
      ;;
    --plugin-version)
      requested_plugin_version="${2:-}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

[ -n "$paper_version" ] || { echo "--paper-version is required" >&2; exit 1; }
[ -n "$paper_dependency_version" ] || { echo "--paper-dependency-version is required" >&2; exit 1; }

python3 - "$PROPERTIES_FILE" "$paper_version" "$paper_dependency_version" "$requested_plugin_version" <<'PY'
import os
import re
import sys
import tempfile
from pathlib import Path

path = Path(sys.argv[1])
paper_version = sys.argv[2]
paper_dependency_version = sys.argv[3]
requested_plugin_version = sys.argv[4]

if not re.fullmatch(re.escape(paper_version) + r"[.]build[.][0-9]+-(alpha|beta|stable)", paper_dependency_version):
    raise SystemExit("Paper dependency must match the requested Paper version and a valid build/channel")
if requested_plugin_version and not re.fullmatch(r"[0-9]+[.][0-9]+[.][0-9]+", requested_plugin_version):
    raise SystemExit("Plugin version must be major.minor.patch")

lines = path.read_text().splitlines(keepends=True)
props = {}
for line in lines:
    if not line or line.startswith("#") or "=" not in line:
        continue
    key, value = line.split("=", 1)
    props[key] = value.strip()

current_plugin_version = props.get("pluginVersion", "")
current_paper_version = props.get("paperApiVersion", "")
current_dependency = props.get("paperApiDependencyVersion", "")

changed = (
    current_paper_version != paper_version
    or current_dependency != paper_dependency_version
    or (requested_plugin_version and requested_plugin_version != current_plugin_version)
)

if not changed:
    next_plugin_version = current_plugin_version
else:
    if requested_plugin_version:
        next_plugin_version = requested_plugin_version
    else:
        match = re.fullmatch(r"([0-9]+)[.]([0-9]+)[.]([0-9]+)", current_plugin_version)
        if not match:
            raise SystemExit(f"Cannot auto-bump non-semver pluginVersion: {current_plugin_version}")
        major, minor, patch = match.groups()
        next_plugin_version = f"{major}.{minor}.{int(patch) + 1}"

props["pluginVersion"] = next_plugin_version
props["paperApiVersion"] = paper_version
props["paperApiDependencyVersion"] = paper_dependency_version

if changed:
    updates = {key: props[key] for key in (
        "pluginVersion", "paperApiVersion", "paperApiDependencyVersion")}
    result = []
    seen = set()
    for line in lines:
        key = line.split("=", 1)[0]
        if key in updates:
            if key in seen:
                raise SystemExit(f"Duplicate property: {key}")
            seen.add(key)
            result.append(f"{key}={updates[key]}\n")
        else:
            result.append(line)
    if seen != updates.keys():
        raise SystemExit("Missing required version properties")
    # Replace atomically, after all validation, preserving other lines verbatim.
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as handle:
        temporary = Path(handle.name)
        handle.write("".join(result))
    try:
        temporary.chmod(path.stat().st_mode)
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)

if changed:
    print(f"Updated Paper pin: {current_paper_version} -> {paper_version}")
    print(f"Updated plugin version: {current_plugin_version} -> {next_plugin_version}")
else:
    print(f"Paper pin is current: {paper_version} ({paper_dependency_version})")

github_output = os.environ.get("GITHUB_OUTPUT")
if github_output:
    with Path(github_output).open("a") as handle:
        handle.write(f"changed={'true' if changed else 'false'}\n")
        handle.write(f"plugin_version={next_plugin_version}\n")
        handle.write(f"paper_api_version={paper_version}\n")
        handle.write(f"paper_dependency_version={paper_dependency_version}\n")
PY
