# Editor ease: the creature and cell editors' usability pass

Status: the features below are **IMPLEMENTED** in the UI layer on branch claude/credit-editor-ease (built, covered
by tests and checked in rendered frames). Their numbers, wording and defaults are **PROPOSED** until the owner
approves them. The parts that need creature-editor code are **PROPOSED** and wait on GitHub issues (see "API
issues" below). Nothing here changes the save schema, the era count, the art pipeline or the milestone scope.

**Scope (CONFIRMED, the owner's words):** "a usability pass on the creature and cell editors' UI layer only:
undo/redo, symmetry toggle, snapping hints, part tooltips with stat effects, and a clearer stats panel. Coordinate
API needs by opening an issue rather than editing creature logic."

So this pass edits only `game/ui/cell_editor.gd`, small hooks in `game/ui/creature_editor_hud.gd`, and new files in
`game/ui/editor_ease/` (no `class_name`; each is preloaded by path). It does not edit `game/scenes/creature/`,
`game/domain/`, `game/systems/` or the UI theme `game/ui/theme/pangaea_theme.tres` (it only uses the theme's type
variations). New strings are plain constants, not wrapped in `tr()`, because the localisation PR (#172) has not
merged.

The Bible lines this follows: §5 (the cell editor previews changes in speed, turning, feeding, defense and energy
demand), §12 (the editor supports undo, redo and mirroring; one authoritative stats service; diminishing returns for
duplicate parts), §14 (UI previews and actions query the same rules) and §19 (inputs shown from bindings; shape,
labels or text alongside colour; tooltips explain trade-offs in plain language with comparable values).

## At a glance

| Feature | Cell editor | Creature editor |
| --- | --- | --- |
| Undo / redo | IMPLEMENTED: one Undo per player action (a whole rim drag, a part and its twin); tooltips and a key line from the bindings | IMPLEMENTED: Undo / Redo tooltips from the bindings. The editor already makes a drag one step. Other keys: plain words until #207 |
| Symmetry | IMPLEMENTED: a toggle, off by default (PROPOSED) | HUD side IMPLEMENTED (hidden). The editor side waits on #204; the editor mirrors today |
| Snapping hints | IMPLEMENTED: the rim drag snaps, with a drawn guide and a hint line | IMPLEMENTED: a placement line for the chosen tool. Showing the spot before the click waits on #203 |
| Part cards | IMPLEMENTED: exact stat effects from `Phenotype.derive` | IMPLEMENTED: exact stat effects from `CreatureStats.of`. A part preview from the editor is asked in #208 |
| Stats panel | IMPLEMENTED: a before → after grid with ▲ / ▼ and signed changes | IMPLEMENTED: a table with each change since the visit began. Numbers from the editor are asked in #208 |
| Theme | IMPLEMENTED: the cell editor uses the game's UI theme | (already themed) |

## Undo and redo

**Cell editor (IMPLEMENTED).** `EditorSession` (`game/domain/editor_session.gd`) checkpoints every operation, and the
rim drag moves the part on every mouse motion, so before this pass one drag took dozens of Undo presses.
`game/ui/editor_ease/undo_steps.gd` counts the session's steps per player action: a press that picks a part on the
rim opens a group and its release closes it, and a Symmetry change to a part and its twin is a group too. One Undo
or Redo then steps the session that many times. The session's own stacks are untouched. An Undo during a drag ends
the drag first. Issue #209 (optional) asks for the same gesture in `EditorSession`, so the grouping can move out of
the UI.

**Both editors (IMPLEMENTED).** The Undo and Redo tooltips name the keys bound to `ui_undo` and `ui_redo`
("Undo the last change (Ctrl+Z)", "Redo the change you undid (Ctrl+Shift+Z / Ctrl+Y)"), or read "Nothing to undo" /
"Nothing to redo" while disabled. `game/ui/editor_ease/shortcut_text.gd` names a binding with its modifiers (Cmd on
macOS when the project remaps Ctrl to Cmd) and controller buttons through `InputPrompts.names_for`. The tooltips are
rebuilt when `InputPrompts.generation` changes. The cell editor's bottom row also has a key line, "Ctrl+Z undo ·
Ctrl+Shift+Z redo · Escape back", for the device in use.

**Creature editor's other keys (PROPOSED, #207).** `CreatureEditor._key()` matches keycodes directly (M, Delete,
Insert, T, Enter, and so on), so the HUD cannot name them from bindings. Until #207 lands, the Delete, Insert,
Mirror, Test drive, Done and Back tooltips say what each does in plain words, without a key.

## Symmetry

**Cell editor (IMPLEMENTED; default off, PROPOSED).** A "Symmetry: off" / "Symmetry: on" toggle (its state is in the
words, not only in the toggle's look). With it on:

- a new part off the middle line is added with a mirrored twin, at a spot where both fit;
- moving, resizing, upgrading or removing either one changes both, as one Undo step;
- Upgrade reads "Upgrade both · N" with the doubled price, and upgrades both;
- Mirror on a part that already has its twin is refused;
- a pair never sits on the middle line (it stays at least `PAIR_EDGE` from it); dragging one across the line swaps
  the two sides;
- a twin that does not fit leaves a single part, and the status line says "No room for its pair: <reason>".

The twin is not stored. It is found at each action by `game/ui/editor_ease/cell_symmetry.gd` (`twin_of`): the part
of the same type, scale and level at the mirrored angle, within `MIRROR_EPS`; ties go to the lower id. A part counts
as central by the same rule `EditorSession.mirror_part()` uses (`|sin(angle)| < CENTRE_SIN`). With Symmetry off,
every action behaves as before this pass (`tests/test_cell_editor.gd` passes unchanged). Off is the default because
it keeps today's behaviour; the owner can switch the default.

**Creature editor (HUD side IMPLEMENTED; editor side PROPOSED, #204).** The creature editor already mirrors: every
new part off the middle line gets a twin, and every limb off the middle plane is a pair. That is the "on" state. The
HUD has `signal symmetry_toggled(on)` and `set_symmetry(on)`, and builds a "Symmetry: on/off" dock button after
Mirror. The button shows only when something is connected to `symmetry_toggled` when `setup()` runs, so no dead
control ships today. Once #204 connects it, the placement line and the part card follow the toggle (off: a part
comes alone and the card shows no pair).

**Where the state lives.** In memory only, never in the save. The cell editor is a new node on each visit
(`game/scenes/main.gd`, `open_cell_editor()`), so its Symmetry starts off every time. The creature toggle only shows
the state the editor gives it.

## Snapping hints

**Cell rim (IMPLEMENTED; numbers PROPOSED).** During a drag, `CellSymmetry.snap()` snaps the part to the middle line
(front or back) or to the spot opposite a part of the same type, within `SNAP_RAD`. Ties go to the middle line, then
to the lower id. `move_selected()` itself still moves exactly; only the drag snaps. While dragging, the rim shows a
faint middle line; when snapped, a solid line with a diamond at the spot, or for a twin a dashed ring and a dashed
chord. With Symmetry on, a dashed mirror axis and a dashed ring on the selected part's twin are drawn. The states
differ in shape, not only in colour. A hint line under the dish reads "Drag a dot round the rim to move its part" at
rest, then "Snapped to the middle line", "Snapped opposite the other <Type>" or "A mirrored pair keeps off the middle
line". Snapping does not avoid a spot another part already holds, as before.

**Creature tools (IMPLEMENTED; the spot itself PROPOSED, #203).** When a tool is chosen, a pill above the dock says
where its part goes and how a click snaps, built by `game/ui/editor_ease/placement_hint.gd` from the part's rule
(`hosts`, `centerline` in `game/data/creature/part_rules.json`) and the editor's own numbers:
`EditorPicking.MIDDLE_SNAP` (shown as 9°) and `EditorPicking.LIMB_END_FROM_U` (shown as "the last 10%"). For example:
"Eye · Click the head or body: within 9° of the middle line it snaps on as one; further out you get a mirrored pair.
It can also sit on another part". The limb tool has its own line. The pill wraps and narrows so it stays between the
palette and the stats panel, and hides with no tool and during the test drive. The card repeats it. The editor
works out the actual spot only on the click, so a marker at the spot before the click needs #203.

## Part cards

One card, `game/ui/editor_ease/part_card.gd`, serves both editors. It is a `PanelContainer` with the theme's
`GlassPanel` look (97% opaque through a stylebox override; the theme file is not edited), a `CaptionLabel` title,
`SmallLabel` lines, and stat rows marked ▲ (better) or ▼ (worse) as well as coloured. It ignores the mouse and sits
beside its anchor, inside the screen. It replaces the engine's default tooltip on the palette, which used to cover
the tile's own name.

**Cell editor (IMPLEMENTED).** On hovering or focusing a palette tile, `game/ui/editor_ease/cell_effects.gd` runs
`Phenotype.derive` on a copy of the working body with the part added where Add would put it (with its twin when
Symmetry is on). The card shows the part's role, only the stats that change (before → after), the diminishing-copies
rule (from the catalog's `diminishing_factor`), "N of M on the body now", "Limit reached" or "No free part slots",
the points it leaves or the points still needed, and where it goes.

**Creature editor (IMPLEMENTED).** On hovering a tool, `game/ui/editor_ease/creature_effects.gd` runs
`CreatureStats.of` on a `BodyCodec` copy of the body with the part added at `EditorPicking.fit_scale`, once as one
part and once as a mirrored pair. The card shows the role, only the stats that change (one part, and "as a pair"
when the centerline rule allows a pair), "Needs a mouth to bite with" where that applies, "No change to bite, sight,
charm or speed: it changes the look" for parts that change only the look, the price of one and of a pair, the points
left, a full body, "Find it in the world to use it" for a part still locked (when the HUD `has_method("is_locked")`),
the refund rule ("Free to take off again before Done; later it refunds 50%", the rate from the editor costs'
`refund_rate`) and where the part goes. Select and Limb have cards too.

The body is read through `hud.owner.working_body()`, read-only and guarded (it checks the method and the session),
and falls back to the editor's reference body `s1_quadruped` when the HUD runs alone, so headless runs log no
errors. Issue #208 asks the editor for a `part_preview(type)` so the HUD need not touch the body at all.

**Stat help (IMPLEMENTED).** Resting the pointer on a stat's name opens the same card with what the stat means, with
the catalog or stage-tuning numbers where there are any (for example "How far it sees: 6 m, plus 3 m per eye, 24 m
at most" in the creature editor, and the speed, turning, sight and defense caps in the cell editor).

## Stats panels

**Cell editor (IMPLEMENTED).** A `GlassPanel` with a "BEFORE → AFTER" caption and a four-column grid: the stat's name,
the parent's value, "→" and the edited value, and a mark with the signed change of the shown numbers ("▲ +1.5"), blank
when equal. A "▲ better ▼ worse" legend explains the marks. Whether a change is better comes from each stat's
direction (lower energy use is better). The after and change columns keep their width, measured from the font, so the
panel does not jump wider at the first change. `CellEditor.stat_lines()` keeps its shape for the existing tests.

**Creature editor (IMPLEMENTED; data from the editor PROPOSED, #208).** The editor sends text lines
(`hud.set_stats(lines)`); `game/ui/editor_ease/stats_rows.gd` reads them back into rows and
`game/ui/editor_ease/stats_panel.gd` shows a table with a "STATS … CHANGE" header and one row each for length, mass,
speed, health, bite and sight. Speed, health, bite and sight are marked ▲ / ▼ (with colour too). Length and mass show a
plain signed change, because a longer or heavier body is a choice, not an upgrade (PROPOSED). Legs, limbs, parts and
bones share two lines ("10 parts · 26 bones (+1)"), then the legend and the selection ("Selected: eye (a pair)",
"vertebra 3 of 9 from the head"). Changes count from the first stats of a visit, or of a new editor session (a
preset, a random creature or Done each start one; the HUD notices the session object change). A line the table
cannot read leaves the editor's own text visible. Issue #208 asks the editor to send the numbers and the selection
directly, guarded by `has_method`, so the HUD can stop parsing text.

## The cell editor's theme (IMPLEMENTED)

The cell editor now uses `game/ui/theme/pangaea_theme.tres` (used, not edited): the title is `LargeLabel`, group headings
`CaptionLabel`, hint lines `SmallLabel`, tools and the bottom row `DockButton`, and Mate `PrimaryButton`. Palette
tiles use the theme's button styles with 6 px padding. Text follows the text-size setting. To fit 130% text, the
dish sits in an `AspectRatioContainer` and fills the remaining room (`DISH_PX`, 480 px, is now its minimum), the tool
row wraps, and the points line can wrap. The dim layer and the test pool keep their own look.

## Numbers (PROPOSED)

| Name | Value | Where | Meaning |
| --- | --- | --- | --- |
| Cell Symmetry default | off | `game/ui/cell_editor.gd` (`symmetry`) | Off keeps today's single adds |
| `SNAP_RAD` | 0.07 rad (about 4°) | `game/ui/editor_ease/cell_symmetry.gd` | How near a rim drag must come to the middle line or a mirrored spot to snap |
| `PAIR_EDGE` | 0.06 rad | `game/ui/editor_ease/cell_symmetry.gd` | How far a mirrored pair keeps off the middle line |
| `CENTRE_SIN` | 0.05 | `game/ui/editor_ease/cell_symmetry.gd` | A part whose angle's sine is below this (in size) is on the middle line (`EditorSession.mirror_part()`'s rule) |
| `MIRROR_EPS` | 0.02 rad | `game/ui/editor_ease/cell_symmetry.gd` | How near the mirrored angle a twin must be |
| `DISH_PX` | 480 px | `game/ui/cell_editor.gd` | The dish's smallest size |
| Card opacity | 0.97 | `game/ui/editor_ease/part_card.gd` (`OPACITY`) | So the card stays readable over the dish |
| Creature stat sense | speed, health, bite, sight better when higher; the rest plain | `game/ui/editor_ease/stats_rows.gd` (`SENSE`) | Which rows get ▲ / ▼ |
| Creature Symmetry | on (the editor's current behaviour) | the editor, after #204 | |
| Middle-line snap shown | 9° | from `EditorPicking.MIDDLE_SNAP` (25/1000 of a turn) | Not a new number |
| Limb end shown | the last 10% | from `EditorPicking.LIMB_END_FROM_U` | Not a new number |

## API issues

The UI works before and after each of these lands: every HUD-side hook checks `has_method` or `has_signal`, and the
asks tell the editor to do the same.

| Issue | Ask | Until it lands |
| --- | --- | --- |
| [#204](https://github.com/jjthillens-oss/pangaea/issues/204) (A) | The creature editor's symmetry switch: `symmetry`, `set_symmetry(on)`, and the connection to the HUD's `symmetry_toggled` | The HUD's toggle stays hidden; parts and limbs off the middle line come as pairs, as today |
| [#207](https://github.com/jjthillens-oss/pangaea/issues/207) (B) | Input actions for the creature editor's keys, and its hint built from the bindings | Only Undo and Redo name keys; the other dock buttons use plain words |
| [#208](https://github.com/jjthillens-oss/pangaea/issues/208) (C) | The stats as numbers (`set_stat_values(now, before)`), the selection (`set_selection(info)`), an optional `part_preview(type)`, public `can_undo()` / `can_redo()`, and one mass for the player | The HUD parses the text lines and reads the working body itself. The HUD receivers `set_stat_values` / `set_selection` are not built yet (they would be once the shapes are agreed) |
| [#203](https://github.com/jjthillens-oss/pangaea/issues/203) (D) | A hover preview of where the chosen part will snap, with a ghost marker and a `tool_hover` report to the HUD | The placement line says how a click snaps, not where. The HUD does not listen for `tool_hover` yet |
| [#209](https://github.com/jjthillens-oss/pangaea/issues/209) (E, optional) | `begin_gesture()` / `end_gesture()` in `EditorSession` | The UI groups the steps (`game/ui/editor_ease/undo_steps.gd`) |

## Known limits and risks

- ▲, ▼ and → are not in the default font (Open Sans SemiBold). They render through the system font fallback, as the
  main branch's existing "Before → after" text already does. Checked under xvfb on Linux; not Windows-verified.
- The Undo and Redo tooltips name the `ui_undo` / `ui_redo` bindings. Off macOS these match the creature editor's
  hardcoded Ctrl+Z, Ctrl+Shift+Z and Ctrl+Y. On macOS the binding reads Cmd while the editor still wants Ctrl; #207
  fixes this.
- The creature editor's Mass line uses 1000 kg/m³ and `CreatureStats.of` uses the stage tuning's 900 kg/m³, so the
  stat help avoids quoting a mass threshold (#208).
- Undo and Redo keep the engine's theme tooltip, not the part card.
- At 130% text a part card can cover part of a neighbouring panel while the pointer rests on a tile. It is a hover
  overlay and closes when the pointer leaves.
- The new strings are not translatable yet (no `tr()` until #172 merges).

## Files

- `game/ui/editor_ease/`: `game/ui/editor_ease/shortcut_text.gd`, `game/ui/editor_ease/undo_steps.gd`,
  `game/ui/editor_ease/cell_symmetry.gd`, `game/ui/editor_ease/cell_effects.gd`, `game/ui/editor_ease/part_card.gd`,
  `game/ui/editor_ease/creature_hud_ease.gd`, `game/ui/editor_ease/stats_rows.gd`,
  `game/ui/editor_ease/stats_panel.gd`, `game/ui/editor_ease/creature_effects.gd`,
  `game/ui/editor_ease/placement_hint.gd`.
- `game/ui/cell_editor.gd`: Symmetry, snapping, the card, the stats panel, the theme.
- `game/ui/creature_editor_hud.gd`: hooks only (the `EditorEase` preload and node, one-line forwards in `wire()`,
  `setup()`, `set_tool()`, `set_stats()` and `set_undo_redo()`, `tool_button()`, `signal symmetry_toggled` and
  `set_symmetry()`).
- Tests: `tests/test_editor_ease_text.gd`, `tests/test_editor_ease_cell.gd`, `tests/test_editor_ease_creature.gd`.
- Frames: `tools/godot/editor_ease_shots.gd` renders the before and after frames in
  `docs/evidence/credit-editor-ease/`.
