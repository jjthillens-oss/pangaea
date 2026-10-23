# Editor core report: dragging bodies, limbs and parts

Status: PROTOTYPE results, 2026-10-23. Built under the owner's standing rule to keep building. The code is in
`prototypes/creature-lab/`. Nothing in `game/` changed. The numbers come from the cloud test machine (4 vCPU Xeon, no
GPU). The live skin ran on lavapipe, Mesa's software Vulkan. Not Windows-verified.

## 1. Split with the cell-stage editor

Agreed with engineering on 2026-10-23 so the game has one editor, not two:

- **Engineering (S4)** owns the cell-stage editor. That covers its scene, palette, cost bar, test space, reproduction
  and saves, all on `Genome` and `EditorSession` (`game/domain/editor_session.gd`, already on main).
- **Creature Lab** owns the creature-stage core: edits to spine bodies (vertebrae, limbs and skin parts), picking,
  gizmos and the live GPU skin.
- The core has the same contract as `EditorSession`, so the S4 scene shell can host it later behind one editor UI:
  - every op returns `{ok, reason}`, and a refused op changes nothing;
  - edits go to a working copy, with snapshot undo and redo;
  - `preview()` gives `phenotype` and `current` stats, `cost`, `affordable` and `errors`;
  - `commit()` validates, checks the points and returns the new body.
- It stays scene-free and deterministic, so it can move into `game/domain` when the creature stage starts.

## 2. What was built

- **`domain/creature_editor_session.gd`**
  - Spine: move, resize, insert and remove a vertebra. The limbs on a vertebra move with it. Removing a vertebra
    also removes its limbs and the parts on them, and the result lists what went.
  - Limbs: add or remove a limb, set its mirror, move, resize, insert or remove a joint. Moving a joint carries the
    rest of the limb by default, so dragging a knee brings the foot along.
  - Parts: add one (with the record's default handles), move, orient, scale, set handles, set mirror, remove.
  - An op is refused when it would add a validation problem the body did not already have. This covers both the
    body rules and the parts' record rules, so a drag stops at the last valid shape. A whole drag
    (`begin_gesture` … `end_gesture`) is one undo step.
  - Cost uses `data/editor_costs.json` (PROPOSED placeholder prices). It charges what was added minus half of what
    was removed. A mirrored limb's joints and a part's twin count twice. Moving, resizing and turning are free.
  - Lineage (genome ids, generation) stays with the caller, because the body description has none.
- **`domain/editor_picking.gd`**
  - `ray_to_skin`: a camera ray to the first skin point. It is clipped to the field's box and steps at a quarter of
    the thinnest radius, so it cannot jump over a thin limb.
  - `anchor_at`: a skin point to a part anchor (host, u, ring, elev). This is the anchor resolver run backwards. A
    click on a mirrored limb's copy gives the anchor on the original, so the part's twin lands under the cursor.
  - `anchor_for_part`: applies the part's record rules to a picked spot:
    - hosts: a foot clicked near a leg tip goes on the leg's end;
    - middle line: a beak snaps onto it, a horn moves off it;
    - an "allowed" part clicked within 2.5% of a turn of the middle line snaps onto it;
    - a part off the middle line gets a twin.
- **Resolver changes** (`domain/anchor_resolver.gd`). Both come from the round trip below.
  - A limb's tip now has an end cap, like the spine's ends: at u = 1000, `elev` leans the part off the axis.
  - At an inner joint the tangent is the mean of the two segments. A part on the outside of a knee then stands out
    from the knee instead of along the thigh.
  - Existing placements do not move: the test bodies have no part at a limb's u = 1000 or exactly on a joint.
- **`editor_lab.tscn`**, a viewer over the core:
  - handles: orange vertebrae, blue joints, green parts;
  - left-drag a handle to move it; with a part tool (keys 1–5) chosen, click the skin to add a part;
  - the wheel thickens or thins the selection; Delete and Insert remove or add; Ctrl+Z and Ctrl+Y undo and redo;
    Enter commits;
  - a vertebra on the middle line stays on it while dragged;
  - the skin rebuilds on the GPU after every accepted edit, or on the GDScript path when the renderer has no
    compute (the compatibility renderer).
  - `--demo` plays a scripted run through the same screen-space calls the mouse uses. It renders
    `editor_lab_demo.mp4`.

## 3. Results

`tests/run_editor_tests.gd`: 80 checks, all passing. They cover:

- all ten Stage 1 bodies open with no cost and no problems;
- spine, limb and part edits, with exact undo and redo (byte-identical text);
- 14 refused ops that leave the body unchanged;
- a six-step drag is one undo step;
- the cost rules, and commit refused over the points;
- determinism (same edits, same SHA-256);
- picking.

Picking round trip: skin point, then anchor, then resolver, measured on every Stage 1 body.

| Body | Within 1% of body length | Median | Worst |
| --- | --- | --- | --- |
| snake | 99.6% | 0.15% | 1.2% |
| quadruped | 99.0% | 0.10% | 1.4% |
| biped | 98.3% | 0.10% | 10.5% |
| hexapod | 98.4% | 0.10% | 3.1% |
| twelve limbs | 96.9% | 0.16% | 1.5% |
| giant limb | 99.3% | 0.08% | 1.7% |
| tiny | 99.0% | 0.08% | 11.4% |
| max vertebrae | 98.7% | 0.18% | 4.4% |
| thin | 99.4% | 0.21% | 1.7% |
| asymmetric | 99.2% | 0.09% | 7.6% |

The misses sit in the fillet where a limb meets the trunk, and on the inside of sharp bends. There, no straight ray
from the line reaches the clicked spot first. The editor shows the part where the resolver puts it, so a click there
lands slightly off but never invisibly.

Live skin while dragging: 20–35 ms per rebuild on software Vulkan at /48 for the quadruped. On the GDScript path
(compatibility renderer, /32) it takes 150–210 ms.

The Stage 1, spine and gait tests still pass after the resolver changes.

## 4. Found while building: growing a body made it invalid (fixed)

The skin grid's cell was the body's longest extent divided by a fixed 48, and each radius had to be at least 1.5 cells.
So lengthening a body coarsened the grid, and thin parts elsewhere fell under the minimum. Adding a tail vertebra to
the quadruped was refused because its toes became too thin.

Fix: each body now gets its own preview grid (`BodyDescription.preview_divisions`). It is 48 as before, or finer when
the thinnest vertebra or joint needs it, up to `preview_divisions_max` (72, in `data/body_rules.json`). Validation
refuses only what the finest grid cannot hold. The ten test bodies keep /48, so nothing about them changes.

| Check | Result |
| --- | --- |
| Quadruped with three tail vertebrae added | Preview /58, 6 120 triangles, closed. Gameplay skin /40, 2 948 triangles, closed |
| How far the quadruped's tail can grow | 6 vertebrae, then the toes are too thin for /72 |
| GPU rebuild, quadruped, software Vulkan | /48 24 ms, /58 36 ms, /72 56 ms |

The gameplay skin needs no change: it already runs coarser than the preview, at /40 or less, and stays closed.

## 5. Limb tool and part turning (added after the merge of PR #59)

- **`EditorPicking.limb_at`** grows a limb from a click with PROPOSED defaults:
  - three joints on the vertebra nearest the click, pointing straight out along the skin normal;
  - 2.5 vertebra radii long, tapering, and thick enough for the finest preview grid;
  - a click off the middle plane makes a mirrored pair; a click on it (the back, the tail tip) makes a single limb.
  - Checks: on the quadruped, biped and hexapod, clicks on the side of the chest, the side of the neck, the top of the
    back and past the tail tip each grow a valid limb (12 checks).
- **Editor Lab.** The limb tool (6 or L) grows the limb and lets the mouse drag its tip out in the same gesture. The
  growth and the drag are one undo step. A selected part shows a yellow ring around its up axis; dragging the ring's
  handle turns the part by the angle the mouse sweeps. Q and E also turn it, and R and F tilt it. The record limits
  apply, so turning past them is refused.
- The demo clip now also grows a pair of arms from the neck, turns a horn with its ring until its record's 60° limit,
  and stretches the tail until the toes are
  too thin for the finest grid.

## 6. Skin built off the main thread

In interactive runs the Editor Lab builds the skin on a worker thread. The handles follow the mouse at once, and the
skin catches up. An edit made while a build runs replaces any queued body, so the worker always builds the newest one.

A local GPU device belongs to the thread that made it, so the worker creates and frees its own. A first try that
started a new thread per build failed with "can only be called from the render thread".

`--demo --async` runs the scripted demo on this path: the clip finishes with no errors and exits cleanly. The plain
demo still builds in step, so every movie frame shows the edit it describes.

## 7. Next (PROPOSED)

1. Hand the core to S4's editor shell when the creature stage starts.
2. Walk the edited creature straight from the editor (Walker Lab on the working body), as a test drive.
