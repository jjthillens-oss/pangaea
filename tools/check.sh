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
#   grow:     (S2) a new omnivore, still and hidden, its ring filled at tick 60, grows by itself
#             once the showcase and calm windows pass; the beat, the badge, the camera, the size-2
#             plankton look and the slot's autosave on the growth are checked, then it saves
#   grow_continue: a new process continues that slot at size 2, at the same place and checkpoint,
#             with the same look, badge, near ghosts and camera
#   band_up:  (S3) a new omnivore at size 2 is filled and forced into band 1 (size 3): the band-up's
#             badge, band 1's pieces, the old band in at most 8 calls, glass flakes, the places line;
#             Go to cradle shows the cradle, its caption, its toast once and the beacon's top; a
#             second growth to size 4 (bead clusters, the engulfer preview), then it saves
#   band_up_continue: a new process continues that slot at size 4 with the old band ready, the
#             cradle, the preview and the places line as saved
#   shore:    a new omnivore at the top size fills its ring and the sea edge rises (in the save and the
#             slot, shown, its arrow and message); teleported onto it, "Swim out to sea?" pauses the
#             pool, Stay in the pool holds the offer until the cell has been out and back, and Swim out
#             to sea opens the Aquatic stage: the slot in the sea with the same lineage and points,
#             and the checkpoint from the pool beside it
#   shore_continue: a new process: the title offers Back to the pool, Continue opens the Aquatic
#             stage, and Back to the pool brings the cell back at the sea edge from the checkpoint
#   creature_build: the creature stage (--creature) on its own store under user://smoke/: the editor
#             grows a pair of neck limbs, adds a maw, eyes and feet, picks a swatch and Done enters
#             the world (the body, colour, points and title); the player eats the nearest fruit, bites
#             a rival, walks back to the nest and evolves (the editor again, generation 2); Escape in
#             the world (the editor), Escape in the editor (the title), then Quit
#   creature_reload: a new process opens the stage from that store and finds the same body SHA-256,
#             points and generation
#   social:   the Social stage preview (--social) on a lineage saved under user://smoke/: the slot's creature
#             walks; refusals in words; the loner backs away from Sing; the band joins on fitting signals;
#             Follow, an unreachable Investigate, Assist to the task's end, the hunter deterred and the scout's
#             warning, Retreat, a faint and recovery, Dismiss; the title's button opens it again; the slot's
#             SHA-256 and folder are unchanged (it never writes the save)
#   menus:    the title, settings and save slots screens driven with controller buttons (d-pad, A,
#             B, LB and RB), a keyboard rebind, the text size, and the pause menu's settings over a
#             run; its own settings file and slots under user://smoke/menus
#   release:  tools/check_release.sh exports the release pack (no game/dev, no tests), starts it
#             and checks it holds the endless content
#   aquatic: the Aquatic stage slice (--aquatic) on a hunter cell lineage saved under user://smoke/: the converted
#             body and lineage, a swim down the route, mating opens the fin and tail editor, Done makes generation 2,
#             Escape saves and returns to the title, the slot holds the v5 aquatic block beside the cell's data, and
#             the stage opens again with the same fish, generation, finds, points and place
# Smoke saves go to user://smoke/, never to the player's slot. Logs are in builds/smoke/ and
# builds/release/.
# Every Godot run has a time limit (tools/bounded.sh: the import 600 s, the unit suite 1200 s, each
# endless phase 120 s (twice its measured time, at least 120 s, build plan B-17), each other run,
# the growth phases among them, 300 s, about three times its usual length on the shared 4-CPU
# container; the suite's
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
bounded 300 "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/smoke/endless_smoke.gd -- --phase=grow --world=endless --slot=user://smoke/grow.json --seed=4246 2>&1 | tee builds/smoke/grow.log
bounded 300 "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/smoke/endless_smoke.gd -- --phase=grow_continue --world=endless --slot=user://smoke/grow.json 2>&1 | tee builds/smoke/grow_continue.log
bounded 120 "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/smoke/endless_smoke.gd -- --phase=band_up --world=endless --slot=user://smoke/band_up.json --seed=4247 2>&1 | tee builds/smoke/band_up.log
bounded 120 "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/smoke/endless_smoke.gd -- --phase=band_up_continue --world=endless --slot=user://smoke/band_up.json 2>&1 | tee builds/smoke/band_up_continue.log
bounded 120 "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/smoke/endless_smoke.gd -- --phase=shore --world=endless --slot=user://smoke/shore.json --seed=4248 2>&1 | tee builds/smoke/shore.log
bounded 120 "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/smoke/endless_smoke.gd -- --phase=shore_continue --world=endless --slot=user://smoke/shore.json 2>&1 | tee builds/smoke/shore_continue.log
bounded 300 "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/smoke/creature_smoke.gd -- --phase=build --creature --slot=user://smoke/creature.json --seed=4242 2>&1 | tee builds/smoke/creature_build.log
bounded 300 "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/smoke/creature_smoke.gd -- --phase=reload --creature --slot=user://smoke/creature.json 2>&1 | tee builds/smoke/creature_reload.log
bounded 300 "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/smoke/social_smoke.gd -- --social --slot=user://smoke/social.json --seed=4260 2>&1 | tee builds/smoke/social.log
bounded 300 "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/smoke/aquatic_smoke.gd -- --aquatic --slot=user://smoke/aquatic.json --seed=4250 2>&1 | tee builds/smoke/aquatic.log
if grep -E "SCRIPT ERROR|^ERROR:" builds/smoke/*.log; then
  echo "Engine or script errors in the smoke logs (builds/smoke/)."
  exit 1
fi
bounded 300 "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/smoke/menus_smoke.gd 2>&1 | tee builds/smoke/menus.log
if grep -E "SCRIPT ERROR|^ERROR:" builds/smoke/menus.log; then
  echo "Engine or script errors in the menus smoke log (builds/smoke/menus.log)."
  exit 1
fi
tools/check_release.sh "$GODOT"
