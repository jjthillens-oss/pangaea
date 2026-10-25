# In-game HUD restyle (credit-hud): frames and layout

The cell HUD (`game/ui/hud.tscn`, `game/ui/hud.gd`, `game/ui/ladder_strip.gd`, `game/ui/meter_ring.gd`) and the
creature world HUD (`game/ui/creature_world_hud.tscn`, `game/ui/creature_world_hud.gd`) take the glass look of the
title menu, in a small, Spore-like layout. The owner's request is CONFIRMED: restyle both HUDs with the title menu's
glass theme, keep them small and Spore-like, keep the HUD API game code calls. The layout and sizes below are
PROPOSED: the owner judges the look.

## Frames

Rendered by `tools/godot/hud_look_shots.gd` under Xvfb with Compatibility (llvmpipe), as JPGs (1600 px max, quality
85). `before_*` is the HUD on main before the restyle; `after_*` is this branch. Each `before_` has an `after_` of
the same name.

| Frame | What it shows | 1920x1080, text 100% | 1920x1080, text 130% | 1280x720, text 100% |
| --- | --- | --- | --- | --- |
| cell_start | endless grazer, seed 4242, 60 frames in: card, ring, controls, points, region toast, ladder strip | [before](before_cell_start_100.jpg) · [after](after_cell_start_100.jpg) | | |
| cell_busy | two meal toasts, the refusal hint, health showing, paused | [before](before_cell_busy_100.jpg) · [after](after_cell_busy_100.jpg) | [before](before_cell_busy_130.jpg) · [after](after_cell_busy_130.jpg) | [before](before_720_cell_busy.jpg) · [after](after_720_cell_busy.jpg) |
| cell_starving | energy 0: the starving banner, the Starving chip, the rested message | [before](before_cell_starving_100.jpg) · [after](after_cell_starving_100.jpg) | [before](before_cell_starving_130.jpg) · [after](after_cell_starving_130.jpg) | [before](before_720_cell_starving.jpg) · [after](after_720_cell_starving.jpg) |
| cell_sunlit | the sunlit tile nearest the origin | [after](after_cell_sunlit_100.jpg) (no before at this size) | [before](before_cell_sunlit_130.jpg) · [after](after_cell_sunlit_130.jpg) | [before](before_720_cell_sunlit.jpg) · [after](after_720_cell_sunlit.jpg) |
| pool_start | the M1 pool, hunter: no growth block, no ladder strip | [before](before_pool_start_100.jpg) · [after](after_pool_start_100.jpg) | | [before](before_720_pool_start.jpg) · [after](after_720_pool_start.jpg) |
| creature_world | the creature field 90 frames after enter_world, at the nest | [before](before_creature_world_100.jpg) · [after](after_creature_world_100.jpg) | | [after](after_720_creature_world.jpg) |
| creature_death | at the nest, the longest notice (the death notice, set by the shot script) with Evolve lit | [after](after_creature_death_100.jpg) | [after](after_creature_death_130.jpg) | [after](after_720_creature_death.jpg) |
| creature_notice | walked off the nest and pressed evolve: the sim's own "Return to the nest to evolve" refusal, and a "+5" flash (set by the shot script). The before frames forced this notice at the nest. | [before](before_creature_notice_100.jpg) · [after](after_creature_notice_100.jpg) | [before](before_creature_notice_130.jpg) · [after](after_creature_notice_130.jpg) | [before](before_720_creature_notice.jpg) · [after](after_720_creature_notice.jpg) |
| creature_away | still off the nest, bit at the air (Bite recharging, a rimmed chip), notice cleared, the controls line timed out (its timer run out by the shot script) and the dock's line naming Move, Orbit and the way back in its place: the HUD as it stays | [after](after_creature_away_100.jpg) | [after](after_creature_away_130.jpg) | [after](after_720_creature_away.jpg) |
| editor_tooltip | the creature editor with the mouse held over Random creature: a real tooltip in the glass `TooltipPanel` / `TooltipLabel` | [after](after_editor_tooltip_100.jpg) | | |

`creature_death`, `creature_away` and `editor_tooltip` were added with the restyle, so they have no before frames.
The tooltip was also looked at in the 130% and 1280x720 renders (not committed): it shows and reads in both.

## Layout (PROPOSED)

Theme additions are append-only (`game/ui/theme/pangaea_theme.tres`): no existing variation changed, so the title
menu, the editors and the menus look as before. New variations: `HudGlass` (glass card, alpha 0.78, margins 18/14,
radius 18), `HudPill` (glass pill, alpha 0.74, margins 18/6, radius 22), `HudBanner` (the starving banner: solid warm
red, 2 px orange rim, radius 18), `SlimEnergyBar` and `SlimHealthBar` (10-12 px bars with the old fills),
`HudValueLabel` (22 px near-white), `HudAccentLabel` (22 px amber), `HudChip` (a `DockButton` whose disabled
state keeps a faint rimmed pill), and glass `TooltipPanel` / `TooltipLabel`.

Cell HUD (rects measured at 1920x1080, text 100%, from `Hud.panel_rects()`):

- Top left: a `HudGlass` card (was a 480 px `HudPanel`), at (32, 28). It is 420 px wide at 100% text and widens
  with the text size (`Hud.status_width()`: 452 px at 115%, 483 px at 130%), so at 130% "Places found at this
  size: 0 of 8" and the lineage stay on one line and the card (x 32..515) still ends 25 px clear of the widest
  centred banner. Vitals first: energy (22 px) with the state chip over a 12 px slim bar, health over a slim bar,
  the shelter chip; then the growth ring and size, the growth line, the places line and the lineage caption.
  `tests/smoke/ui_smoke.gd` STATUS_W is 420 (it runs at 100% text).
- Top right: the points as a `HudPill` (diamond, 22 px value, amber flash), at (1559, 28), 329x43; toasts as
  `HudPill`s under it.
- Top centre: the starving banner, the one strong solid panel on screen (`HudBanner`: warning icon, two lines of
  32 px text and the gentle 1 Hz pulse, unchanged; as on main, the reduce-flashing setting softens the hurt
  vignette and holds the ring's pulse but not this one), at (602, 28), 716x117; the one-off
  message (`show_message`, which main.gd also uses for the shore texts) as a `HudPill` under it.
- Bottom centre: the idea and refusal hints as `HudPill`s with 22 px amber text; the hint ends at y 952, above the
  edge arrows' band.
- Bottom left: the controls as a `HudGlass` card with a "CONTROLS" caption, at (32, 756), 496x296.
- Bottom right: the ladder strip as a `HudGlass` card, 532 px wide (its slots are 76 px, were 68, so the
  three-word captions break only between words at 130%).
- Fonts that code sizes now follow the text-size setting: the meter ring's digit (`MeterRing.font_size()`), the
  ladder captions (`LadderStrip.caption_size()`) and the world overlay's labels (`Hud.WorldOverlay.font_size()`).

Creature world HUD:

- Top left, the goals: a small `HudGlass` card (at least 300 px) with the name and generation (caption), the points
  with the diamond and the "+N" flash (22 px), and a goal line: "Goal: evolve at the nest", or "At the nest: E to
  evolve" with the bound key while the creature stands at the nest.
- Top centre: one notice at a time as a `HudPill` with 22 px amber text (one style: `show_notice` carries no tone).
- Bottom centre: the dock, a `HudGlass` bar with the health text (22 px) over a 280x12 slim bar, and three ability
  chips (`HudChip`, the editor's `DockButton` look), each named by its first binding ("F  Bite", "R  Sing",
  "E  Evolve"). The chips only show state: Evolve lights (the dock's cyan, dark text) while the creature is at the
  nest, and Bite dims while its cooldown runs (a faint pill with a light 1 px rim and grey-blue text, so it reads
  as recharging, not gone; its text measures about 7.5:1 on the pill at 1920x1080 and 5.9:1 at 1280x720, where
  the thinner strokes lower the measured peak). They take no focus and no mouse and never act: the keys do. Bite
  is left out for a body with no mouth, as in the controls line.
- Above the dock, the controls line as a `HudPill`, unchanged in wording. It shows for 15 s (`KEYS_HINT_S`) each
  time the world opens and again when the device in use changes (keys and mouse to a controller or back), then
  fades. A rebinding is made in the settings, outside the world, so it shows the next time the world opens.
- As the controls line fades, a small caption line in the dock fades in and stays: the keys the chips do
  not name, "WASD  Move   ·   Middle drag  Orbit   ·   Escape  Back to the editor" (on a controller "Left stick",
  "Right stick" and "B"), named from the bindings like the line itself. So moving, orbiting and the way out never
  leave the screen, as Bible 19 asks of tutorial prompts ("can be dismissed or revisited"). The creature world has
  no pause menu (Escape goes straight back to the editor), and the pool's pause menu lists only the cell's
  controls, so this dock line is where those keys stay. Whether the timed line should also drop the abilities the
  chips already show is the owner's call (tests read Bite, Evolve, Move and "Back to the editor" in its text, not
  its visibility). The dock line's row is always laid out (alpha 0 while the controls line is up), so the dock
  keeps one height and does not jump up when the line comes in.
- Every control in the creature HUD ignores the mouse, so the middle-drag orbit reaches the camera.
- The top right is empty now: the points moved into the goal card.
- The cell HUD was restyled in place, per the lead's decision for this job: energy and health stay top left as a
  glass card, with the growth ring, the controls card bottom left and the ladder strip bottom right, and no ability
  row. Main's handbook "Small HUD" pillar (`docs/director/HANDBOOK.md`; backlog Q-02 in
  `docs/director/backlog.json`: goals top left, abilities bottom centre, one progress bar) arrived after this job
  started; the creature HUD follows it, and Q-02 for the cell stage stays open.

## Verified (IMPLEMENTED)

- The HUD API is unchanged: every public method, property, const, static, signal hookup and node path the brief
  lists, and the private fields the creature tests read (`_hint_text`, `_name_text`, `_points_text`,
  `_points_flash`).
- The creature HUD's chips, goal line, mouse handling and controls-line timeout have their own unit tests in
  `tests/test_creature_world_hud.gd` (a stub world), added at the round 1 reviewers' request; the file is outside
  the job brief's list, so the lead signs it off in the PR, together with the added test in `tests/test_ui_text.gd`
  (below), which the brief's wording for that file ("only to read the real nodes' variations") does not cover. Both
  were added at reviewers' request, only add coverage and loosen no bound. They cover the chips' names and a
  rebinding shown when the world opens again, Evolve lit only at the nest, Bite dimmed while it recharges and absent
  without a mouth, no mouse or focus anywhere, the goal line, and the controls line timing out with the dock's line
  then naming the move, orbit and way-out keys, and the line coming back on a real device change
  (`InputPrompts.note` with a controller button) and when the world opens again.
- The status card's width has a unit test at each text size (`tests/test_ui_text.gd`,
  `test_the_hud_words_sized_in_code_follow_the_text_size`): 420, 452 and 483 px at 100, 115 and 130%, and at the
  largest size the card still ends 16 px clear of the widest centred banner or message (x 540).
- Targeted tests for round 2's fixes: `tests/run_tests.gd -- --only=test_creature_world_hud,test_ui_text,
  test_creature_world_scene` 36 tests, 0 failed; `tests/smoke/ui_smoke.gd` (`--world=pool`) 44 checks, 0 failed;
  the creature smoke 56 and 11 checks, 0 failed. Round 1's look probe with its current gates
  (`tools/godot/look_probe.gd -- --scenes=hud,starving,sunlit`): 29 gates, 0 failed (the cell HUD's look has not
  changed since).
- Round 3 (the dock keeps one height): the dock's key line is always laid out and only its alpha changes. In the
  shot logs the dock is (609, 944) 701x108 both while the controls line is up and after it goes, at 1920x1080 100%
  and 1280x720, and (577, 930) 765x122 both times at 130%. `tests/test_creature_world_hud.gd` checks that the line
  keeps its row and is faded out while the controls line is up; run against round 2's HUD code that check fails (5
  tests, 1 failed). The headless runner does not lay out hidden-in-tree controls, so the dock's height itself is
  checked in the frames, not in the unit test. With the final test: `--only=test_creature_world_hud,test_ui_text` 29
  tests, 0 failed. With this HUD code (earlier drafts of the test):
  `test_creature_world_hud,test_creature_world_scene,test_creature_stage,test_ui_text` 46 tests, 0 failed;
  `tests/smoke/ui_smoke.gd` 44 checks, 0 failed; the creature smoke 56 and 11 checks, 0 failed. The creature after
  frames were re-rendered. The full check below was not rerun for this round's change (one HUD file's fade handling,
  a test and docs; main's merge 4b0ef032 added docs only).
- The full check at HEAD 462efb26: tools/check.sh steps run via check_full.sh, with the unit suite's limit raised
  to 3600 s for this 4-CPU container. It took 1779 s. Unit suite: 1931 tests, 3 failed (38 soak skipped): two
  timing gates in the container's baseline for main (`test_endless_cost::test_slow_a_sleeper_costs_at_most_2_us`
  and `test_endless_cost::test_slow_the_30_s_after_a_growth_cost_at_most_14_yardsticks_a_window`), and
  `test_world_gen::test_slow_band_1_chunks_cost_as_band_0s` (size 4: max 658 us, 7.49 yardsticks; limits 600 us
  and 7.0), a timing gate not in the baseline that passed in round 1's full check and passes alone on this branch
  (45 tests, 0 failed; size 4 max 568 us, 6.24 yardsticks); this branch changes no world-gen code. Every step
  after the unit suite passed: the play, ui, endless, grow, band, shore, aquatic, creature (build 56, reload 11)
  and menus (61) smokes, the error-log gate, and the release pack and content probes.
- Contrast, measured on the after frames against the median of each panel (the glass): over the creature field's
  sand and sky the goal card, notice pill, controls pill and dock read 13.1-14.3:1 for near-white text, 10.6-11.5:1
  for amber, 8.1-8.8:1 for SmallLabel and 7.6-8.3:1 for the caption, at 1920x1080 (100% and 130%) and 1280x720. In
  the cell, over the brightest white shell behind the card, near-white reads 11.1:1 and the caption 6.5:1; the
  hint, controls and strip panels read at least 14.7:1 near-white and 8.6:1 caption in the busy, starving and
  sunlit frames.
- At 130% nothing in either HUD is clipped and no HUD panel overlaps another; the banner and message stay clear of
  the card and the points pill.

## Known, not changed here

- At 130% the pool's starving arrow and its "Food 5 m" label (`game/scenes/pool/starving_arrow.gd`, outside this
  job's files) can sit under the message pill, as they already did before the restyle.
- In Compatibility the sunlit tile reads about as dark as the home water, so the sunlit frames do not show a bright
  sea; contrast there was measured against what renders.
- No hunger bar: the player creature has no hunger in the creature sim (every creature starts with fullness 1.0,
  but only rivals' fullness changes, and `CreatureWorldSim.player()` does not return it), so the dock shows health
  only. Sing never dims: `player()` does not expose the sing cooldown. Both need a read-only addition to the
  creature systems code, which other agents own: issues #205 (sing cooldown) and #206 (player hunger, an owner
  decision first).
- On a controller, B is both Sing (`creature_social` is bound to joypad button 1 in `project.godot`) and Back to the
  editor (`ui_cancel`'s controller B, which `SettingsService.UI_PAD` adds at start in `apply_bindings`), so pressing
  B to sing also leaves the world. This was so before the restyle (main's key line showed the same names); the chips
  only make it visible. `project.godot` and the creature code belong to other owners, so it is not changed here.
- `tests/test_world_hud.gd` still feeds the pre-glass panel rects into its pip test as fixed inputs, and its
  comment still says they are read off the running game. Refreshed from the new layout, its west-south-west case
  no longer lies under the controls card, so the scenario would need the owner's approval to change. The shot
  script prints the real rects (`panels cell_...` lines) for that refresh.
- The look probe passes with its current gates (29 gates, 0 failed, above). Its old `--look=baseline` set names
  the teal M1 look of ecb1eee (`vignette_hue`, `starving_contrast`); it fails for any build of main's blue sea and
  red hurt vignette, not because of the HUD.
