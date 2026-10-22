#!/usr/bin/env bash
# Imports assets, runs the test suite, the M0 boot check and the scene smokes, then fails if any
# smoke log holds an engine or script error. Usage: tools/check.sh [path-to-godot]
#   launch:   the main scene opens and runs 300 frames (start screen, nothing saved)
#   found:    a new grazer lineage eats, starves and recovers, then saves and quits to the title;
#             hunter and omnivore lineages eat too
#   continue: a new process continues that lineage and finds the same body, points and place
#   hud:      for every body, the starving banner and a long message stay clear of the HUD's
#             status and points panels
# Smoke saves go to user://smoke/, never to the player's slot. Logs are in builds/smoke/.
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/toolchain.env
GODOT="${1:-${GODOT:-.toolchain/Godot_v${GODOT_RELEASE}_linux.x86_64}}"
"$GODOT" --headless --path . --import
"$GODOT" --headless --path . --script res://tests/run_tests.gd
"$GODOT" --headless --path . res://game/scenes/boot.tscn -- --smoke
rm -rf builds/smoke
mkdir -p builds/smoke
"$GODOT" --headless --fixed-fps 60 --path . --quit-after 300 -- --slot=user://smoke/launch.json 2>&1 | tee builds/smoke/launch.log
"$GODOT" --headless --fixed-fps 60 --path . --script res://tests/smoke/play_smoke.gd -- --phase=found --slot=user://smoke/slot_1.json --seed=4242 2>&1 | tee builds/smoke/found.log
"$GODOT" --headless --fixed-fps 60 --path . --script res://tests/smoke/play_smoke.gd -- --phase=continue --slot=user://smoke/slot_1.json 2>&1 | tee builds/smoke/continue.log
"$GODOT" --headless --fixed-fps 60 --path . --script res://tests/smoke/ui_smoke.gd 2>&1 | tee builds/smoke/ui.log
if grep -E "SCRIPT ERROR|^ERROR:" builds/smoke/*.log; then
  echo "Engine or script errors in the smoke logs (builds/smoke/)."
  exit 1
fi
