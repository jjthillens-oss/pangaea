#!/usr/bin/env bash
# Launches the exported Windows build on Windows (CI's windows-launch job runs it in Git Bash on a
# windows runner), so a build reaches Joshua only after it has started on Windows at least once.
# check_release.sh starts the same pack with the Linux engine; this catches what only the Windows
# templates can break (a pack the exe cannot read, a missing DLL, a renderer that cannot start).
#   launch:   Pangaea.exe, headless, runs its main scene 120 frames (start screen, nothing saved)
#   rendered: Pangaea-dev.exe with a real window and renderer runs the --perf-tour (the ForageBot
#             swims a grazer in the pool for 90 s, then it quits). A CI runner has no GPU, so the
#             renderer is whatever Windows offers there (usually its software adapter), and the
#             frame rate means nothing; what counts is that the pool renders, the tour finishes
#             and nothing errors. The runner has no Vulkan and no audio device, so Godot switches
#             to Direct3D 12 and the dummy audio driver; those errors are the runner's, not the
#             build's, and are the only ones let through (RUNNER_ONLY).
#   grow:     (S2) Pangaea-dev.exe, rendered, runs --perf-tour=grow: the cell still in the sea for
#             40 s with two growths, the second with reduce motion. Its frame times mean nothing
#             here either (S2G26 is a run on Joshua's machine); what counts is that the growth
#             renders on Windows, the tour finishes and nothing errors.
#             It runs at 640 x 360. At 1280 x 720 it did not finish in 300 s on the runner's
#             software adapter (e2 at eb93634 and dd137d7): the route is 2,400 sim ticks, and the
#             engine steps at most 8 a frame, so a slow enough frame holds the route back. Each
#             route prints its progress every 10 s ("Perf tour (grow): 20 s, route tick 1180,
#             9.3 FPS"), so a run stopped at the limit shows how far it got, and each growth step
#             as it is taken. At 640 x 360 on e2 081adb9 it printed no progress line at all in
#             300 s (it finishes in about 45 s on Linux in both renderers, llvmpipe and lavapipe, also
#             after the launch and rendered runs), so a watch thread now prints where the main thread
#             is after 10 s without a frame ("Perf tour (grow): no frame for 30 s, in the draw at
#             route tick 300").
# release_probe.gd does not run here: a release exe ignores --script. check_release.sh runs it on
# the same pack.
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
# Errors the runner causes (no Vulkan driver, no audio device), matched on the error or its "at:".
RUNNER_ONLY='Vulkan instance extension|drivers/vulkan/rendering_context_driver_vulkan|WASAPI|drivers/wasapi/'
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
run rendered "$BUILD/Pangaea-dev.exe" --resolution 1280x720 -- --perf-tour
run grow "$BUILD/Pangaea-dev.exe" --resolution 640x360 -- --perf-tour=grow --slot=user://smoke/windows_grow.json

for name in rendered grow; do
  if ! grep -q "^Perf tour: .* FPS average" "$LOGS/$name.log"; then
    echo "The perf tour did not finish in the $name run."
    status=1
  fi
done
# Each error with the line after it (its "at:"), less the runner's own.
errors="$(awk -v skip="$RUNNER_ONLY" '
  FNR == 1 && pending != "" { if (pending !~ skip) print file ": " pending; pending = "" }
  pending != "" { if ((pending " " $0) !~ skip) print file ": " pending; pending = "" }
  /SCRIPT ERROR|^ERROR:/ { pending = $0; file = FILENAME }
  END { if (pending != "" && pending !~ skip) print file ": " pending }
' "$LOGS"/*.log)"
if [ -n "$errors" ]; then
  echo "$errors"
  echo "Engine or script errors while starting the Windows build ($LOGS/)."
  status=1
fi
if [ "$status" -ne 0 ]; then
  echo "The Windows build failed its launch check."
  exit 1
fi
echo "The Windows build starts cleanly on Windows."
