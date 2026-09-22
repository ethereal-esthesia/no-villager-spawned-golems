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

python3 - "$PAPER_API" "$PAPER_CHANNEL" "$current_paper_version" "$current_paper_dependency" > "$paper_info_file" <<'PY'
import json
import re
import sys
import urllib.parse
import urllib.request

api_base, requested_channel, current_version, current_dependency = sys.argv[1:5]
api_base = api_base.rstrip("/")
requested_channel = requested_channel.upper()

def request_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": "no-villager-spawned-golems-release/1.0 (https://github.com/ethereal-esthesia/no-villager-spawned-golems)"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)

def version_key(version):
    main, _, suffix = version.partition("-")
    parts = []
    for part in re.split(r"([0-9]+|[A-Za-z]+)", main):
        if not part or part in ".-+_":
            continue
        if part.isdigit():
            parts.append((1, int(part)))
        else:
            parts.append((0, part.lower()))
    suffix_parts = tuple((1, int(p)) if p.isdigit() else (0, p.lower())
                         for p in re.findall(r"[0-9]+|[A-Za-z]+", suffix))
    return (parts, not bool(suffix), suffix_parts)

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
    current_build = re.fullmatch(re.escape(current_version) + r"[.]build[.]([0-9]+)-([a-z]+)", current_dependency)
    if not current_build:
        raise SystemExit(f"Cannot compare current Paper dependency: {current_dependency}")
    if (version_key(version) < version_key(current_version)
            or (version == current_version and int(build_id) <= int(current_build[1]))):
        # Keep a newer explicitly selected version/build, even on another channel.
        version = current_version
        build_id, channel = current_build.groups()
        dependency_version = current_dependency
        print("No newer eligible Paper build; keeping current pin.", file=sys.stderr)
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
      echo "paper_dependency_version=$current_paper_dependency"
      echo "paper_build=$latest_paper_build"
      echo "paper_channel=$latest_paper_channel"
    } >> "$GITHUB_OUTPUT"
  fi
  exit 0
fi

# Share the metadata writer so unrelated properties are preserved.
"$ROOT_DIR/scripts/update-to-paper-version.sh" \
  --paper-version "$latest_paper_version" \
  --paper-dependency-version "$latest_paper_dependency"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "paper_build=$latest_paper_build"
    echo "paper_channel=$latest_paper_channel"
  } >> "$GITHUB_OUTPUT"
fi
