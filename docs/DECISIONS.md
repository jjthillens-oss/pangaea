# Decisions log

Each entry: date, decision, reason, impact, approval. Status labels follow the Bible: CONFIRMED, PROPOSED, IMPLEMENTED.

## 2026-10-22 · Engine stays Godot 4 (CONFIRMED)
Owner approved starting M0 in Godot 4 rather than switching to three.js. Reason: Windows builds, animation, physics and simulation come with the engine. The HTML prototype moves to `prototypes/web-cell/` as a tuning sandbox.

## 2026-10-22 · Toolchain pinned (IMPLEMENTED, owner review pending)
Godot 4.7.2-stable and Blender 5.2.2 LTS. See `docs/TOOLCHAIN.md`.

## 2026-10-22 · Product name (open)
The repository and window title use **Pangaea**; the Bible calls the project **GENESIS**. Treated as codename for now. Owner to confirm the player-facing name.

## 2026-10-22 · Thrive code not reused (owner aware)
Thrive is GPL-3.0. Reusing its code would require releasing Pangaea under the GPL. It may be studied as a design reference only, unless the owner decides otherwise.

## Open decisions (from Bible section 26)
- Era names and boundaries.
- First playable (M1) scope and starting body plans.
- Microscopic camera and movement constraint (the boot scene camera is not a decision).
- Visual reference package and benchmark scene (M2).
- Baseline Windows hardware for the 60 fps at 1080p target.
- Difficulty presets and death recovery rules.
- Git LFS for large `.blend` sources.
