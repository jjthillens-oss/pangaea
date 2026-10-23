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
#   (each phase above runs the M1 pool, --world=pool; the four below run the endless sea, S1)
#   endless_out: a new omnivore swims 300 tm east (rebases, unloads, new tiles), then saves
#   endless_continue: a new process finds the cell at its absolute place within 1e-6 tm with the
#             same chunks; the column, the arrow home and its distance; a meal ghost keeping its
#             place across a dev rebase; a far death whose respawn message waits for the respawn
#   fps30, fps144: the same sim state hash at tick 1,200 at 30 and at 144 frames a second
#   release:  tools/check_release.sh exports the release pack (no game/dev, no tests), starts it
#             and checks it holds the endless content
# Smoke saves go to user://smoke/, never to the player's slot. Logs are in builds/smoke/ and
# builds/release/.
# Every Godot run has a time limit (tools/bounded.sh: the import 600 s, the unit suite 1200 s, each
# endless phase 120 s (twice its measured time, at least 120 s, build plan B-17), each other run
# 300 s, about three times its usual length on the shared 4-CPU container; the suite's
# limit holds the S1 fast and slow budgets, build plan B-13), so a hang fails the check with exit
# code 124 and the output so far instead of running until CI's job timeout (40 minutes);
# tools/test_bounded.sh checks those limits first, and that a Ctrl-C still stops it all.
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/toolchain.env
GODOT="${1:-${GODOT:-.toolchain/Godot_v${GODOT_RELEASE}_linux.x86_64}}"

source tools/bounded.sh

tools/test_bounded.sh
bounded 600 "$GODOT" --headless --path . --import
bounded 1200 "$GODOT" --headless --path . --script res://tests/run_tests.gd
bounded 300 "$GODOT" --headless --path . res://game/scenes/boot.tscn -- --smoke
rm -rf builds/smoke
mkdir -p builds/smoke
bounded 300 "$GODOT" --headless --fixed-fps 60 --path . --quit-after 300 -- --world=pool --slot=user://smoke/launch.json 2>&1 | tee builds/smoke/launch.log
bounded 300 "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/smoke/play_smoke.gd -- --world=pool --phase=found --slot=user://smoke/slot_1.json --seed=4242 2>&1 | tee builds/smoke/found.log
bounded 300 "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/smoke/play_smoke.gd -- --world=pool --phase=continue --slot=user://smoke/slot_1.json 2>&1 | tee builds/smoke/continue.log
bounded 300 "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/smoke/ui_smoke.gd -- --world=pool 2>&1 | tee builds/smoke/ui.log
bounded 300 "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/smoke/play_smoke.gd -- --world=pool --phase=die_and_quit --slot=user://smoke/death.json --seed=4243 2>&1 | tee builds/smoke/die_and_quit.log
bounded 300 "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/smoke/play_smoke.gd -- --world=pool --phase=after_death --slot=user://smoke/death.json 2>&1 | tee builds/smoke/after_death.log
bounded 120 "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/smoke/endless_smoke.gd -- --phase=endless_out --world=endless --slot=user://smoke/endless.json --seed=4244 2>&1 | tee builds/smoke/endless_out.log
bounded 120 "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/smoke/endless_smoke.gd -- --phase=endless_continue --world=endless --slot=user://smoke/endless.json 2>&1 | tee builds/smoke/endless_continue.log
bounded 120 "$GODOT" --headless --fixed-fps 30 --resolution 1280x720 --path . --script res://tests/smoke/endless_smoke.gd -- --phase=fps --world=endless --seed=4245 --slot=user://smoke/fps30.json --fps-out=user://smoke/fps_30.json 2>&1 | tee builds/smoke/fps30.log
bounded 120 "$GODOT" --headless --fixed-fps 144 --resolution 1920x1080 --path . --script res://tests/smoke/endless_smoke.gd -- --phase=fps --world=endless --seed=4245 --slot=user://smoke/fps144.json --compare=user://smoke/fps_30.json 2>&1 | tee builds/smoke/fps144.log
if grep -E "SCRIPT ERROR|^ERROR:" builds/smoke/*.log; then
  echo "Engine or script errors in the smoke logs (builds/smoke/)."
  exit 1
fi
tools/check_release.sh "$GODOT"
