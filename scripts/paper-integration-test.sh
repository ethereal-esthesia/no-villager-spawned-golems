#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
TEST_DIR="$BUILD_DIR/paper-integration-test"
SERVER_DIR="$TEST_DIR/server"
SERVER_LOG="$SERVER_DIR/logs/latest.log"
SERVER_STDIN="$TEST_DIR/server.stdin"
PAPER_API="${PAPER_API:-https://fill.papermc.io/v3/projects/paper}"
PAPER_MINECRAFT_VERSION="${PAPER_MINECRAFT_VERSION:-$(sed -n 's/^paperApiVersion=//p' "$ROOT_DIR/gradle.properties" | head -n 1)}"
PAPER_DEPENDENCY_VERSION="$(sed -n 's/^paperApiDependencyVersion=//p' "$ROOT_DIR/gradle.properties" | head -n 1)"
PAPER_DEPENDENCY_CHANNEL="$(printf '%s' "$PAPER_DEPENDENCY_VERSION" | sed -n 's/.*-\([^-]*\)$/\1/p' | tr '[:lower:]' '[:upper:]')"
PAPER_CHANNEL="${PAPER_CHANNEL:-${PAPER_DEPENDENCY_CHANNEL:-STABLE}}"
PUMPKIN_PLACE_DELAY_SECONDS="${PUMPKIN_PLACE_DELAY_SECONDS:-2}"
RUN_ID="NVSG_$(date +%s)_$$"
SERVER_PID=""
KEEPALIVE_PID=""

cleanup() {
  set +e
  if [ -p "$SERVER_STDIN" ]; then
    printf 'stop\n' > "$SERVER_STDIN" 2>/dev/null
  fi

  if [ -n "$SERVER_PID" ]; then
    wait "$SERVER_PID" >/dev/null 2>&1
  fi

  if [ -n "$KEEPALIVE_PID" ]; then
    kill "$KEEPALIVE_PID" >/dev/null 2>&1
  fi
}

trap cleanup EXIT INT TERM

resolve_paper_download() {
  python3 - "$PAPER_API" "$PAPER_MINECRAFT_VERSION" "$PAPER_CHANNEL" <<'PY'
import json
import re
import sys
import urllib.parse
import urllib.request

api_base, requested_version, requested_channel = sys.argv[1:4]
api_base = api_base.rstrip("/")
requested_channel = requested_channel.upper()

def request_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": "no-villager-spawned-golems-ci/1.0"})
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

    suffix_parts = []
    for part in re.split(r"([0-9]+|[A-Za-z]+)", suffix):
        if not part or part in ".-+_":
            continue
        if part.isdigit():
            suffix_parts.append((1, int(part)))
        else:
            suffix_parts.append((0, part.lower()))

    release_rank = 1 if not suffix else 0
    return (parts, release_rank, suffix_parts)

def all_project_versions():
    project = request_json(api_base)
    if isinstance(project, list):
        versions = project
    else:
        versions = project.get("versions", [])
    if isinstance(versions, dict):
        flattened = []
        for group_versions in versions.values():
            flattened.extend(group_versions)
        versions = flattened

    version_ids = []
    for entry in versions:
        if isinstance(entry, str):
            version_ids.append(entry)
            continue

        if not isinstance(entry, dict):
            continue

        version = entry.get("version", entry)
        if isinstance(version, str):
            version_ids.append(version)
        elif isinstance(version, dict) and version.get("id"):
            version_ids.append(version["id"])

    return sorted(set(version_ids), key=version_key, reverse=True)

def latest_build_for(version):
    encoded_version = urllib.parse.quote(version, safe="")
    builds = request_json(f"{api_base}/versions/{encoded_version}/builds")
    candidates = [
        build for build in builds
        if requested_channel in {"LATEST", "ANY"}
        or str(build.get("channel", "")).upper() == requested_channel
    ]
    if not candidates:
        return None
    return sorted(candidates, key=lambda build: int(build.get("id", 0)), reverse=True)[0]

if requested_version:
    resolved_version = requested_version
    build = latest_build_for(resolved_version)
    if build is None:
        raise SystemExit(f"No {requested_channel} Paper builds found for {resolved_version}.")
else:
    resolved_version = None
    build = None
    for candidate_version in all_project_versions():
        candidate_build = latest_build_for(candidate_version)
        if candidate_build is not None:
            resolved_version = candidate_version
            build = candidate_build
            break
    if build is None:
        raise SystemExit(f"No {requested_channel} Paper builds found.")

download = build.get("downloads", {}).get("server:default", {})
download_url = download.get("url", "")
if not download_url:
    raise SystemExit(f"Paper build {resolved_version} #{build.get('id')} has no server download URL.")

print(download_url)
print(resolved_version)
print(build.get("id"))
PY
}

wait_for_log() {
  local needle="$1"
  local timeout_seconds="${2:-60}"
  local elapsed=0

  while [ "$elapsed" -lt "$timeout_seconds" ]; do
    if [ -f "$SERVER_LOG" ] && grep -F "$needle" "$SERVER_LOG" >/dev/null 2>&1; then
      return 0
    fi

    if [ -n "$SERVER_PID" ] && ! kill -0 "$SERVER_PID" >/dev/null 2>&1; then
      echo "Paper server exited while waiting for: $needle" >&2
      tail -n 120 "$SERVER_LOG" 2>/dev/null || true
      return 1
    fi

    sleep 1
    elapsed=$((elapsed + 1))
  done

  echo "Timed out waiting for log line: $needle" >&2
  tail -n 120 "$SERVER_LOG" 2>/dev/null || true
  return 1
}

send_command() {
  local command="$1"
  printf '%s\n' "$command" > "$SERVER_STDIN"
}

log_contains() {
  local needle="$1"
  [ -f "$SERVER_LOG" ] && grep -F "$needle" "$SERVER_LOG" >/dev/null 2>&1
}

wait_for_test_chunk() {
  local marker="${RUN_ID}_CHUNK_LOADED"
  local attempts=0

  while [ "$attempts" -lt 30 ]; do
    send_command "execute if loaded 0 80 0 run say ${marker}"
    sleep 1

    if log_contains "$marker"; then
      return 0
    fi

    attempts=$((attempts + 1))
  done

  echo "Timed out waiting for test chunk 0,0 to load." >&2
  tail -n 120 "$SERVER_LOG" >&2
  exit 1
}

"$ROOT_DIR/gradlew" -p "$ROOT_DIR" clean build

paper_info_file="$TEST_DIR/paper-download.txt"
mkdir -p "$TEST_DIR"
resolve_paper_download > "$paper_info_file"
paper_url="$(sed -n '1p' "$paper_info_file")"
paper_version="$(sed -n '2p' "$paper_info_file")"
paper_build="$(sed -n '3p' "$paper_info_file")"

echo "Testing against Paper $paper_version build #$paper_build"

if [ "$paper_version" != "$PAPER_MINECRAFT_VERSION" ]; then
  echo "Resolved Paper version $paper_version does not match pinned version $PAPER_MINECRAFT_VERSION." >&2
  exit 1
fi

rm -rf "$TEST_DIR"
mkdir -p "$SERVER_DIR/plugins" "$SERVER_DIR/logs"
cp "$BUILD_DIR/libs"/NoVillagerSpawnedGolems-*-paper-"$PAPER_MINECRAFT_VERSION".jar "$SERVER_DIR/plugins/"
curl -fsSL --retry 3 --connect-timeout 15 -o "$SERVER_DIR/paper.jar" "$paper_url"

cat > "$SERVER_DIR/eula.txt" <<'EOF'
eula=true
EOF

cat > "$SERVER_DIR/server.properties" <<'EOF'
allow-flight=true
difficulty=peaceful
enable-command-block=true
enable-query=false
enable-rcon=false
enforce-secure-profile=false
gamemode=creative
level-name=world
motd=NoVillagerSpawnedGolems CI
online-mode=false
server-ip=127.0.0.1
server-port=25566
spawn-protection=0
view-distance=6
simulation-distance=6
EOF

mkfifo "$SERVER_STDIN"
tail -f /dev/null > "$SERVER_STDIN" &
KEEPALIVE_PID="$!"

(
  cd "$SERVER_DIR"
  java -Xms1G -Xmx2G -jar paper.jar nogui < "$SERVER_STDIN"
) &
SERVER_PID="$!"

wait_for_log "Done (" 180
wait_for_log "[NoVillagerSpawnedGolems] Enabled. Allowing iron golem spawn reasons: [BUILD_IRONGOLEM]" 30

echo "Test 1: golem created with block commands spawns"
send_command "forceload add 0 0"
wait_for_test_chunk
send_command "kill @e[type=minecraft:iron_golem]"
sleep 1
send_command "fill -4 80 -4 4 86 4 minecraft:air"
send_command "fill -4 79 -4 4 79 4 minecraft:stone"
send_command "setblock 0 80 0 minecraft:iron_block"
send_command "setblock 0 81 0 minecraft:iron_block"
send_command "setblock -1 81 0 minecraft:iron_block"
send_command "setblock 1 81 0 minecraft:iron_block"
sleep "$PUMPKIN_PLACE_DELAY_SECONDS"
send_command "setblock 0 82 0 minecraft:carved_pumpkin"
sleep 2
send_command "execute positioned 0 80 0 if entity @e[type=minecraft:iron_golem,distance=..8] run say ${RUN_ID}_COMMAND_BUILD_PRESENT"
sleep 1

if ! log_contains "${RUN_ID}_COMMAND_BUILD_PRESENT"; then
  echo "FAIL: command block placement did not create an iron golem near 0 80 0." >&2
  tail -n 120 "$SERVER_LOG" >&2
  exit 1
fi

echo "Test 2: spawn command does not create a golem"
send_command "kill @e[type=minecraft:iron_golem]"
sleep 1
send_command "summon minecraft:iron_golem 0 80 0"
sleep 2
send_command "execute positioned 0 80 0 if entity @e[type=minecraft:iron_golem,distance=..8] run say ${RUN_ID}_SUMMON_PRESENT"
sleep 1

if log_contains "${RUN_ID}_SUMMON_PRESENT"; then
  echo "FAIL: /summon left an iron golem near 0 80 0." >&2
  tail -n 120 "$SERVER_LOG" >&2
  exit 1
fi

echo "Paper integration tests passed."
