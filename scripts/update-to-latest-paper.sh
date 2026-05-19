#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PAPER_API="${PAPER_API:-https://fill.papermc.io/v3/projects/paper}"
PAPER_CHANNEL="${PAPER_CHANNEL:-STABLE}"
PROPERTIES_FILE="$ROOT_DIR/gradle.properties"

current_plugin_version="$(sed -n 's/^pluginVersion=//p' "$PROPERTIES_FILE" | head -n 1)"
current_paper_version="$(sed -n 's/^paperApiVersion=//p' "$PROPERTIES_FILE" | head -n 1)"
current_paper_dependency="$(sed -n 's/^paperApiDependencyVersion=//p' "$PROPERTIES_FILE" | head -n 1)"

paper_info_file="$ROOT_DIR/build/latest-paper.txt"
mkdir -p "$ROOT_DIR/build"

python3 - "$PAPER_API" "$PAPER_CHANNEL" > "$paper_info_file" <<'PY'
import json
import re
import sys
import urllib.parse
import urllib.request

api_base, requested_channel = sys.argv[1:3]
api_base = api_base.rstrip("/")
requested_channel = requested_channel.upper()

def request_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": "no-villager-spawned-golems-release/1.0"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)

def version_key(version):
    parts = []
    for part in re.split(r"([0-9]+|[A-Za-z]+)", version):
        if not part or part in ".-+_":
            continue
        if part.isdigit():
            parts.append((1, int(part)))
        else:
            parts.append((0, part.lower()))
    return parts

project = request_json(api_base)
versions = project.get("versions", [])
if isinstance(versions, dict):
    flattened = []
    for group_versions in versions.values():
        flattened.extend(group_versions)
    versions = flattened

for version in sorted(set(versions), key=version_key, reverse=True):
    encoded_version = urllib.parse.quote(version, safe="")
    builds = request_json(f"{api_base}/versions/{encoded_version}/builds")
    candidates = [
        build for build in builds
        if str(build.get("channel", "")).upper() == requested_channel
    ]
    if not candidates:
        continue

    build = sorted(candidates, key=lambda build: int(build.get("id", 0)), reverse=True)[0]
    channel = str(build.get("channel", requested_channel)).lower()
    build_id = str(build.get("id"))
    dependency_version = f"{version}.build.{build_id}-{channel}"
    print(version)
    print(build_id)
    print(channel)
    print(dependency_version)
    raise SystemExit(0)

raise SystemExit(f"No {requested_channel} Paper builds found.")
PY

latest_paper_version="$(sed -n '1p' "$paper_info_file")"
latest_paper_build="$(sed -n '2p' "$paper_info_file")"
latest_paper_channel="$(sed -n '3p' "$paper_info_file")"
latest_paper_dependency="$(sed -n '4p' "$paper_info_file")"

if [ "$current_paper_version" = "$latest_paper_version" ] && [ "$current_paper_dependency" = "$latest_paper_dependency" ]; then
  echo "Paper pin is current: $current_paper_version ($current_paper_dependency)"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
      echo "changed=false"
      echo "plugin_version=$current_plugin_version"
      echo "paper_api_version=$current_paper_version"
      echo "paper_build=$latest_paper_build"
      echo "paper_channel=$latest_paper_channel"
    } >> "$GITHUB_OUTPUT"
  fi
  exit 0
fi

IFS=. read -r major minor patch rest <<< "$current_plugin_version"
if [ -z "${major:-}" ] || [ -z "${minor:-}" ] || [ -z "${patch:-}" ] || [ -n "${rest:-}" ]; then
  echo "Cannot auto-bump non-semver pluginVersion: $current_plugin_version" >&2
  exit 1
fi

next_plugin_version="$major.$minor.$((patch + 1))"

cat > "$PROPERTIES_FILE" <<EOF
pluginVersion=$next_plugin_version
paperApiVersion=$latest_paper_version
paperApiDependencyVersion=$latest_paper_dependency
EOF

echo "Updated Paper pin: $current_paper_version -> $latest_paper_version"
echo "Updated plugin version: $current_plugin_version -> $next_plugin_version"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "changed=true"
    echo "plugin_version=$next_plugin_version"
    echo "paper_api_version=$latest_paper_version"
    echo "paper_build=$latest_paper_build"
    echo "paper_channel=$latest_paper_channel"
  } >> "$GITHUB_OUTPUT"
fi
