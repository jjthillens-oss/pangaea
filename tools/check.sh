#!/usr/bin/env bash
# Imports assets, runs the test suite, the M0 boot check and the scene smokes, then fails if any
# smoke log holds an engine or script error. Usage: tools/check.sh [path-to-godot]
#   launch:   the main scene opens and runs 300 frames (start screen, nothing saved)
#   found:    a new grazer lineage eats, starves and recovers, dies and continues; then the
#             threats: creatures drawn and listed in the debug panel, F9 and F10, caught by an
#             ambush hunter (tell, hit, notice, death saved), continued sheltered, caught again
#             soon after (a longer shelter), and an edge arrow for a hunter below the screen; then
#             it saves and quits to the title; hunter and omnivore lineages eat too. Last, the
#             grazer continues and the window's close button saves and quits through "Save
#             first?", ending the game
#   continue: a new process continues that lineage and finds the same body, points, deaths and
#             place, its creatures repopulated and the cell sheltered
#   ui:       with a saved lineage, the replace-lineage confirm opens on Cancel; for every body,
#             the starving banner and a long message stay clear of the HUD's side panels
#   die_and_quit: a new omnivore eats dev carrion and is caught; the death is saved at once, so
#             the window's close button at the death notice quits with no dialog
#   after_death:  a new process continues that slot: the points the death left, the cell at its
#             checkpoint and sheltered, the death last in its history
#   release:  tools/check_release.sh exports the release pack (no game/dev, no tests) and starts it
# Smoke saves go to user://smoke/, never to the player's slot. Logs are in builds/smoke/ and
# builds/release/.
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
"$GODOT" --headless --fixed-fps 60 --path . --script res://tests/smoke/play_smoke.gd -- --phase=die_and_quit --slot=user://smoke/death.json --seed=4243 2>&1 | tee builds/smoke/die_and_quit.log
"$GODOT" --headless --fixed-fps 60 --path . --script res://tests/smoke/play_smoke.gd -- --phase=after_death --slot=user://smoke/death.json 2>&1 | tee builds/smoke/after_death.log
if grep -E "SCRIPT ERROR|^ERROR:" builds/smoke/*.log; then
  echo "Engine or script errors in the smoke logs (builds/smoke/)."
  exit 1
fi
tools/check_release.sh "$GODOT"
