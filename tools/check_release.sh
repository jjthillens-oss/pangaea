#!/usr/bin/env bash
# Starts the release build the way a player's Pangaea.exe does, without game/dev and tests, and
# fails on any engine or script error. check.sh's runs use the project, where game/dev exists, so
# only this catches a release pack that cannot start (Godot still exits 0 when main.gd fails to
# parse, so the logs are what count).
#   launch: the pack's main scene runs 120 frames (start screen, nothing saved)
#   probe:  tools/release_probe.gd checks the start screen is up, Main has no dev layer,
#           --perf-tour is ignored, the creature stage opens with its part tools, saves and
#           enters the world, and the pack holds nothing from game/dev or tests
# With no pack given it exports the release preset's pack to builds/release/Pangaea.pck (a pack
# export needs no export templates). CI passes builds/windows/Pangaea.exe after the export, so the
# exe it uploads is the one checked. Both runs start in an empty folder, so a res:// path missing
# from the pack cannot fall through to the project. Logs are in builds/release/. The export has
# 600 s and each start 300 s, so a hang fails the check (exit code 124) with the output so far.
# Usage: tools/check_release.sh [path-to-godot] [pack-or-exe]
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/toolchain.env
GODOT="${1:-${GODOT:-.toolchain/Godot_v${GODOT_RELEASE}_linux.x86_64}}"

source tools/bounded.sh

case "$GODOT" in */*) GODOT="$(realpath "$GODOT")" ;; esac
LOGS="$PWD/builds/release"
PROBE="$PWD/tools/release_probe.gd"
mkdir -p "$LOGS"
rm -f "$LOGS"/*.log
PACK="${2:-}"
if [ -z "$PACK" ]; then
  PACK="$LOGS/Pangaea.pck"
  if ! bounded 600 "$GODOT" --headless --path . --export-pack "Windows Desktop" "$PACK" > "$LOGS/export.log" 2>&1; then
    tail -n 30 "$LOGS/export.log"
    echo "Could not export the release pack (log: $LOGS/export.log)."
    exit 1
  fi
fi
PACK="$(realpath "$PACK")"
RUN_DIR="$(mktemp -d)"
trap 'rm -rf "$RUN_DIR"' EXIT
echo "Starting the release pack $PACK"
status=0
(cd "$RUN_DIR" && bounded 300 "$GODOT" --headless --fixed-fps 60 --main-pack "$PACK" --quit-after 120 -- --slot=user://smoke/release.json) 2>&1 | tee "$LOGS/launch.log" || status=1
(cd "$RUN_DIR" && bounded 300 "$GODOT" --headless --fixed-fps 60 --main-pack "$PACK" --script "$PROBE" -- --slot=user://smoke/release.json --perf-tour) 2>&1 | tee "$LOGS/probe.log" || status=1
if grep -E "SCRIPT ERROR|^ERROR:" "$LOGS"/*.log; then
  echo "Engine or script errors while exporting or starting the release pack ($LOGS/)."
  status=1
fi
if [ "$status" -ne 0 ]; then
  echo "The release pack failed its check."
  exit 1
fi
echo "The release pack starts cleanly."
