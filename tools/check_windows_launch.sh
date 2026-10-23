#!/usr/bin/env bash
# Launches the exported Windows build on Windows (CI's windows-launch job runs it in Git Bash on a
# windows runner), so a build reaches Joshua only after it has started on Windows at least once.
# check_release.sh starts the same pack with the Linux engine; this catches what only the Windows
# templates can break (a pack the exe cannot read, a missing DLL, a renderer that cannot start).
#   launch:   Pangaea.exe, headless, runs its main scene 120 frames (start screen, nothing saved)
#   probe:    Pangaea.exe, headless, runs tools/release_probe.gd (start screen up, no dev layer)
#   rendered: Pangaea-dev.exe with a real window and renderer runs the --perf-tour (the ForageBot
#             swims a grazer in the pool for 90 s, then it quits). A CI runner has no GPU, so the
#             renderer is whatever Windows offers there (usually its software adapter), and the
#             frame rate means nothing; what counts is that the pool renders and nothing errors.
# The exes are GUI programs whose output may not reach a pipe, so each run also writes Godot's own
# log (--log-file); both go into the run's log. Each run starts in an empty folder, so nothing can
# fall through to the repository, and has 300 s. Logs are in builds/windows-launch/. Godot still
# exits 0 when a script fails to parse, so the logs count too.
# Usage: tools/check_windows_launch.sh [build-dir]   (default builds/windows)
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/bounded.sh

BUILD="$(realpath "${1:-builds/windows}")"
LOGS="$PWD/builds/windows-launch"
# A path Godot on Windows can read (C:/...), unchanged elsewhere.
native() { if command -v cygpath > /dev/null; then cygpath -m "$1"; else echo "$1"; fi; }
PROBE="$(native "$PWD/tools/release_probe.gd")"
mkdir -p "$LOGS"
rm -f "$LOGS"/*.log "$LOGS"/*.txt
for exe in Pangaea.exe Pangaea-dev.exe; do
  if [ ! -f "$BUILD/$exe" ]; then
    ls -la "$BUILD"
    echo "The build has no $exe."
    exit 1
  fi
done
RUN_DIR="$(mktemp -d)"
trap 'rm -rf "$RUN_DIR"' EXIT
cd "$RUN_DIR"

status=0
run() {
  local name="$1"
  shift
  echo "== $name: $*"
  local exe="$1"
  shift
  local godot_log="$LOGS/$name.godot.txt"
  local code=0
  bounded 300 "$exe" --log-file "$(native "$godot_log")" "$@" > "$LOGS/$name.log" 2>&1 || code=$?
  if [ -f "$godot_log" ]; then
    echo "-- Godot log" >> "$LOGS/$name.log"
    cat "$godot_log" >> "$LOGS/$name.log"
  fi
  cat "$LOGS/$name.log"
  if [ "$code" -ne 0 ]; then
    echo "$name exited with $code"
    status=1
  fi
}

run launch "$BUILD/Pangaea.exe" --headless --fixed-fps 60 --quit-after 120 -- --slot=user://smoke/windows_launch.json
run probe "$BUILD/Pangaea.exe" --headless --fixed-fps 60 --script "$PROBE" -- --slot=user://smoke/windows_launch.json --perf-tour
run rendered "$BUILD/Pangaea-dev.exe" --resolution 1280x720 -- --perf-tour

if ! grep -q "^PASS Main opens on the start screen" "$LOGS/probe.log"; then
  echo "The release probe did not report the start screen."
  status=1
fi
if grep -E "SCRIPT ERROR|^ERROR:" "$LOGS"/*.log; then
  echo "Engine or script errors while starting the Windows build ($LOGS/)."
  status=1
fi
if [ "$status" -ne 0 ]; then
  echo "The Windows build failed its launch check."
  exit 1
fi
echo "The Windows build starts cleanly on Windows."
