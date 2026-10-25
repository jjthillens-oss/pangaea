# In-game HUD restyle (credit-hud): frames and layout

The cell HUD (`game/ui/hud.tscn`, `game/ui/hud.gd`, `game/ui/ladder_strip.gd`, `game/ui/meter_ring.gd`) and the
creature world HUD (`game/ui/creature_world_hud.tscn`, `game/ui/creature_world_hud.gd`) take the glass look of the title menu, in a small,
Spore-like layout. The owner's request is CONFIRMED: restyle both HUDs with the title menu's glass theme, keep them
small and Spore-like, keep the HUD API game code calls. The layout and sizes below are PROPOSED: the owner judges the
look.

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
| creature_notice | "Return to the nest to evolve" (forced by the shot script, so it shows at the nest) and a "+5" flash | [before](before_creature_notice_100.jpg) · [after](after_creature_notice_100.jpg) | [before](before_creature_notice_130.jpg) · [after](after_creature_notice_130.jpg) | [before](before_720_creature_notice.jpg) · [after](after_720_creature_notice.jpg) |
| creature_away | walked off the nest and bit at the air (Bite recharging), with the longest notice, the death notice | [after](after_creature_away_100.jpg) | [after](after_creature_away_130.jpg) | [after](after_720_creature_away.jpg) |

`creature_away` was added with the dock, so it has no before frame.

## Layout (PROPOSED)

Theme additions are append-only (`game/ui/theme/pangaea_theme.tres`): no existing variation changed, so the title
menu, the editors and the menus look as before. New variations: `HudGlass` (glass card, alpha 0.78, margins 18/14,
radius 18), `HudPill` (glass pill, alpha 0.74, margins 18/6, radius 22), `HudBanner` (the starving banner: solid warm
red, 2 px orange rim, radius 18), `SlimEnergyBar` and `SlimHealthBar` (10-12 px bars with the old fills),
`HudValueLabel` (22 px near-white), `HudAccentLabel` (22 px amber), and glass `TooltipPanel` / `TooltipLabel`.

Cell HUD (rects measured at 1920x1080, text 100%, from `Hud.panel_rects()`):

- Top left: a 420 px `HudGlass` card (was a 480 px `HudPanel`), at (32, 28). Vitals first: energy (22 px) with the
  state chip over a 12 px slim bar, health over a slim bar, the shelter chip; then the growth ring and size, the
  growth line, the places line and the lineage caption. `tests/smoke/ui_smoke.gd` STATUS_W is 420.
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
  chips in the editor's `DockButton` style, each named by its first binding ("F  Bite", "R  Sing", "E  Evolve").
  The chips only show state: Evolve lights (the dock's cyan, dark text) while the creature is at the nest, and Bite
  dims (grey text, 4.4:1) while its cooldown runs. They take no focus and no mouse and never act: the keys do.
  Bite is left out for a body with no mouth, as in the hint line. Above the dock, the controls line as a `HudPill`
  (22 px), unchanged in wording, since tests and players read it.
- Every control in the creature HUD ignores the mouse, so the middle-drag orbit reaches the camera.
- The top right is empty now: the points moved into the goal card.

## Verified (IMPLEMENTED)

- The HUD API is unchanged: every public method, property, const, static, signal hookup and node path the brief
  lists, and the private fields the creature tests read (`_hint_text`, `_name_text`, `_points_text`,
  `_points_flash`).
- Tests on this branch: `tests/run_tests.gd -- --only=test_ui_text,test_growth_hud,test_world_hud,
  test_threat_indicators,test_creature_world_scene,test_creature_stage,test_settings,test_menus,test_look_probe,
  test_creature_editor_hud` 135 tests, 0 failed; `tests/smoke/ui_smoke.gd` (`--world=pool`) 44 checks, 0 failed; `tests/smoke/play_smoke.gd`
  found phase 184 checks, 0 failed; `tests/smoke/creature_smoke.gd` build 56 checks and reload 11 checks, 0 failed.
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
- The player creature has no hunger value in the creature sim (only rivals have fullness), so the dock shows
  health only. Sing never dims: `CreatureWorldSim.player()` does not expose the sing cooldown. Both would need a
  read-only addition to the creature systems code, which other agents own.
- `tests/test_world_hud.gd` still feeds the old panel rects into its pip test: refreshed from the new layout, its
  west-south-west case no longer lies under the controls card, so the scenario would need the owner's approval to
  change.
- The look probe's baseline gates `vignette_hue` and `starving_contrast` fail on this branch (`--look=baseline
  --scenes=hud,starving,sunlit`). They name the teal M1 look of ecb1eee; the pool now draws a blue sea and a red
  hurt vignette. The vignette is measured with no HUD layer and the cell sits clear of every HUD panel, and this
  branch does not change the vignette shader or the 3D scene; not re-run on main.
