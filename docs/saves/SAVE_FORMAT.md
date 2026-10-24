# Save format reference

Status: **IMPLEMENTED** schema v4 at base commit `94fb2a6` (2026-10-24). All `path:line` citations in the v4 sections refer to that commit. This document describes the shipped reader and writer; it proposes no schema change. The v2 reference is retained below as dated history.

## Files, slots and recovery

The title offers three slots, `user://saves/slot_1.json` through `slot_3.json`; the slot number is clamped to 1–3. Slot 1 remains the earlier default, and tests can redirect `SaveSlots.folder` (`game/systems/save_slots.gd:8-16`, `game/systems/game_session.gd:27`). A slot name is independent of the lineage and genome IDs inside its file (`game/domain/save_game.gd:167-169`, `tests/test_persistence.gd:74-98`).

Writing validates the state, stamps `saved_at_unix`, writes `<slot>.tmp`, reloads that temporary file, and checks lineage, seed and creature continuity. A good primary becomes `<slot>.bak` before the temporary file becomes primary; a corrupt primary is set aside as `<slot>.corrupt-<timestamp>` without deleting its backup. Refused and failed writes remove their temporary file (`game/systems/persistence_service.gd:43-89`). Reading changes no files: it tries primary, a valid temporary file if the primary is absent, then backup, and returns an explanation if none load (`game/systems/persistence_service.gd:92-136`). Migration operates on a deep copy; a newer version or missing migration is refused (`game/systems/persistence_service.gd:139-156`).

## Current JSON schema: v4

The writer emits exactly the following **20 required top-level keys**. Missing and unknown keys fail loading; typed fields report problems rather than silently defaulting. JSON whole numbers may parse as integral floats, which the reader accepts when finite (`game/domain/save_game.gd:40-48,162-227`, `game/domain/json_values.gd:9-43`). The table distinguishes structural validation from semantic validation.

| Key | JSON type, meaning and accepted value | Source |
| --- | --- | --- |
| `schema_version` | Writer emits `4`. Loader accepts a numeric version and casts it to an integer before migration/refusal; fractional values are not separately rejected. | `game/domain/save_game.gd:30,162-165`; `game/systems/persistence_service.gd:140-156` |
| `build_id` | Text identifying the writer; no content restriction. | `game/domain/save_game.gd:50,165,196` |
| `world_seed` | Whole number from 0 through 2^53 inclusive, the exactly representable JSON integer range. | `game/domain/save_game.gd:31-32,101-104,166,197` |
| `lineage_id` | Stable lineage ID text, checked against the `lineage_` format. | `game/domain/save_game.gd:52,95-96,167,198`; `game/domain/stable_id.gd:12-16` |
| `era` | One of the seven strings in `SaveGame.ERAS`; those names remain proposed design labels. | `game/domain/save_game.gd:33-34,97-98,168,199` |
| `genome` | Object with the nested fields below; lineage ID must match the enclosing save, and parts must pass the catalog. | `game/domain/save_game.gd:105-110,169,200-201`; `game/domain/genome.gd:60-106` |
| `adaptation_points` | Whole number of unspent points, 0 or greater. | `game/domain/save_game.gd:55-56,99-100,170,202` |
| `creature` | `{}` before a creature exists, otherwise an object with `name`, `body`, `generation`, `history` below. | `game/domain/save_game.gd:16-23,132,136-159,171,203-207` |
| `lineage_history` | Nonempty ordered array. A founding event has `generation`, `genome_id`, `event`; element shapes are not checked by this loader. | `game/domain/save_game.gd:59-60,111-112,172,208` |
| `discoveries` | Array of exact `{type, id, size}` objects, described below. | `game/domain/save_game.gd:38-39,61-62,130-131,173,209-212,250-260` |
| `relationships` | Array; entries have no current schema validation. | `game/domain/save_game.gd:63,174,213` |
| `settlements` | Array; entries have no current schema validation. | `game/domain/save_game.gd:64,175,214` |
| `world_changes` | Array; entries have no current schema validation. | `game/domain/save_game.gd:65,176,215` |
| `player` | Object with exactly `position`, `energy`, `health` (below). | `game/domain/save_game.gd:44,66-67,113-120,177,216` |
| `pending_transactions` | Array; entries have no current schema validation or approved cross-era transaction contract. | `game/domain/save_game.gd:68,178,217` |
| `growth` | Exact `{size, meter}` object, described below. | `game/domain/save_game.gd:45,69-70,121,179,218,230-236` |
| `checkpoint` | Exact `{x_am, y_am, heading, size}` object, described below. | `game/domain/save_game.gd:46,71-73,122,180,219,239-247` |
| `spawn` | Explicit `null` (use checkpoint) or exact `{x_am, y_am, heading}` object. Missing is an error. | `game/domain/save_game.gd:47,74-75,123-127,181,220-225,239-247` |
| `gen_version` | Whole generator version, at least 1. | `game/domain/save_game.gd:76-77,128-129,182,225` |
| `saved_at_unix` | Whole Unix timestamp in seconds; writer stamps it, loader has no range check. | `game/domain/save_game.gd:78,183,226`; `game/systems/persistence_service.gd:48` |

### Nested fields

Every field named here is required unless marked optional. `genome` writes `schema_version: 1`, `genome_id`, `lineage_id`, `parent_genome_id` (text), `generation` (whole number ≥1), `appearance` (object), `parts` (array), and `next_part_number` (whole number). The two active IDs must pass stable-ID validation. A missing or nonpositive `next_part_number` is reconstructed from the highest `part_N` ID; that is a genome compatibility exception. Appearance has no nested schema enforced here (`game/domain/genome.gd:6-17,60-68,109-147`). Each part has `id` (unique text), `type` (known catalog part), `angle` (finite radians within ±π), and `scale` (finite catalog range, currently 0.5–2). Optional `level` defaults to 1 and, when present, must be a permitted whole level for that type. Catalog category and part-count rules also apply (`game/domain/genome.gd:13-15,69-106`, `game/data/part_catalog.json:5-11`).

A nonempty `creature` has `name` (nonblank text), `body` (object), `generation` (whole number ≥1), and `history` (array). On the real persistence path, the body also passes the creature rules and part rules; its internal keys are owned by the body codec, including extra look keys. Creature history element shapes are not validated here (`game/domain/save_game.gd:16-23,136-159`, `game/systems/persistence_service.gd:34-40`). One lineage shares `adaptation_points` between cell and creature (`game/domain/save_game.gd:18-19`).

`player.position` is a three-element world coordinate array; the endless world stores absolute am. The save validator checks its length but not each coordinate's finite numeric type. `player.energy` and `player.health` each accept `null` (fresh) or a finite number ≥0; neither has a maximum here (`game/domain/save_game.gd:66-67,113-120`). `growth.size` and `checkpoint.size` are whole numbers 1–10; `growth.meter` is finite and ≥0, with no maximum checked. The checkpoint and non-null spawn use finite `x_am`, `y_am` coordinates and a finite heading in radians (`game/domain/save_game.gd:35-37,45-47,69-75,230-247,276-283`). A discovery uses exactly `type` (`place`, `landmark`, or `food`), nonempty text `id`, and whole `size` 1–10 (`game/domain/save_game.gd:38-39,48,250-260`).

### Complete minimal v4 example

This includes every v4 key, a valid starting genome and a founding event. It represents a microscopic run with no creature, empty discoveries and the default checkpoint; it is intended to load through `PersistenceService.load_from()` with the current part catalog (`game/domain/save_game.gd:40-48,83-90,162-184`, `game/systems/persistence_service.gd:115-136`).

```json
{
  "schema_version": 4,
  "build_id": "example",
  "world_seed": 2026,
  "lineage_id": "lineage_3f9a1c07b2e84d65",
  "era": "microscopic",
  "genome": {
    "schema_version": 1,
    "genome_id": "genome_8d21e6a4f03b9c57",
    "lineage_id": "lineage_3f9a1c07b2e84d65",
    "parent_genome_id": "",
    "generation": 1,
    "appearance": {"hue": 0.45, "pattern": "plain"},
    "parts": [
      {"id": "part_1", "type": "mouth_jaw", "angle": 0.0, "scale": 1.0},
      {"id": "part_2", "type": "flagellum", "angle": 3.14159, "scale": 1.0}
    ],
    "next_part_number": 3
  },
  "adaptation_points": 0,
  "creature": {},
  "lineage_history": [{"generation": 1, "genome_id": "genome_8d21e6a4f03b9c57", "event": "founded"}],
  "discoveries": [],
  "relationships": [],
  "settlements": [],
  "world_changes": [],
  "player": {"position": [0.0, 0.0, 0.0], "energy": null, "health": null},
  "pending_transactions": [],
  "growth": {"size": 1, "meter": 0.0},
  "checkpoint": {"x_am": 0.0, "y_am": 9.0, "heading": -1.5708, "size": 1},
  "spawn": null,
  "gen_version": 1,
  "saved_at_unix": 0
}
```

## Migrations and Continue behavior

The registered path is **v1 → v2 → v3 → v4**, applied to an in-memory copy in that order. v1 → v2 adds `adaptation_points: 0` (`game/systems/save_migrations.gd:8-20`; `tests/fixtures/save_v1.json:1`). v2 → v3 adds `creature: {}` for a lineage that has not entered the creature stage (`game/systems/save_migrations.gd:23-28`; `tests/fixtures/save_v2_step2.json:1`). v3 had two parallel preview variants: creature lineage and S2 cell growth. v3 → v4 fills whichever half is missing. If `creature` is absent, it adds `{}`. If `growth` is absent, it adds `growth: {size: 1, meter: 0.0}`, home `checkpoint: {x_am: 0.0, y_am: 9.0, heading: -1.5708, size: 1}`, `spawn: null`, `gen_version: 1`, and `player.energy`/`health: null` when player is an object. It preserves existing discoveries and position; wrong-typed player data is left to fail validation (`game/systems/save_migrations.gd:31-51`; `tests/fixtures/save_v3_creature.json:1`, `tests/fixtures/save_v3_s2.json:1`; `tests/test_persistence.gd:550-586,656-704,734-772`). Loading does not rewrite the original file (`game/systems/persistence_service.gd:94-112,139-156`).

**Continue uses seeded restart, not an exact live-tick resume.** The owner kept the 2026-10-24 contract: durable cell, body, lineage, points and checkpoint return, while the pool is regenerated from its seed. Tick, RNG stream and live actor state are not persisted in these 20 keys. `GameSession.continue_run()` constructs a new `PoolSim` from the loaded save (`docs/DECISIONS.md:671-677`, `game/systems/game_session.gd:177-190`, `game/domain/save_game.gd:40-48`).

## Slot inspection and changing the schema

`SaveSlots.peek_all()` reads the three slots without writing. `GameSession.peek_slot()` exposes status, source, errors and a summary; deletion removes primary, backup and temporary files but leaves `.corrupt-*` files (`game/systems/save_slots.gd:27-55`, `game/systems/game_session.gd:121-145`). Settings belong to `SettingsService`/`UserSettings`, outside the run save (`game/domain/save_game.gd:40-48`, `game/systems/settings_service.gd:1-6`).

For a future field, start from **v4**. A v5 requires owner approval under the “Save schema v4” decision before changing `SaveGame.SCHEMA_VERSION`, the exact key list, writer, reader or validator. Then add one immutable 4 → 5 migration with explicit defaults, fixtures for old variants, save/load and recovery tests, and same-lineage/body checks. Do not relabel v4 data or insert a field without a version change (`docs/DECISIONS.md:731-738`, `game/domain/save_game.gd:25-30,40-48`, `game/systems/save_migrations.gd:3-13`, `tests/test_persistence.gd:235-252`).

## Historical reference: v2 (2026-10-22)

At commit `f544488`, v2 added `adaptation_points: 0` to v1. Its writer had 15 required top-level keys: `schema_version`, `build_id`, `world_seed`, `lineage_id`, `era`, `genome`, `adaptation_points`, `lineage_history`, `discoveries`, `relationships`, `settlements`, `world_changes`, `player`, `pending_transactions` and `saved_at_unix`. `player` then held only `position`. That format is retained as migration input, not relabelled as current v4 (`game/systems/save_migrations.gd:16-28`, `tests/fixtures/save_v2_step2.json:1`, `game/domain/save_game.gd:40-48`).

### Complete minimal v2 example (historical migration input)

```json
{
  "schema_version": 2,
  "build_id": "example",
  "world_seed": 2026,
  "lineage_id": "lineage_3f9a1c07b2e84d65",
  "era": "microscopic",
  "genome": {
    "schema_version": 1,
    "genome_id": "genome_8d21e6a4f03b9c57",
    "lineage_id": "lineage_3f9a1c07b2e84d65",
    "parent_genome_id": "",
    "generation": 1,
    "appearance": {"hue": 0.45, "pattern": "plain"},
    "parts": [
      {"id": "part_1", "type": "mouth_jaw", "angle": 0.0, "scale": 1.0},
      {"id": "part_2", "type": "flagellum", "angle": 3.14159, "scale": 1.0}
    ],
    "next_part_number": 3
  },
  "adaptation_points": 0,
  "lineage_history": [{"generation": 1, "genome_id": "genome_8d21e6a4f03b9c57", "event": "founded"}],
  "discoveries": [],
  "relationships": [],
  "settlements": [],
  "world_changes": [],
  "player": {"position": [0.0, 0.0, 0.0]},
  "pending_transactions": [],
  "saved_at_unix": 0
}
```

## Remaining gaps (PROPOSED)

- The version reader casts numeric `schema_version` to an integer, so a fractional value such as 4.5 is not rejected as fractional. A stricter check needs its own regression test (`game/systems/persistence_service.gd:140-147`).
- Era changes have no approved transaction payload, pre-transition checkpoint protocol or migration tests. `pending_transactions` is only array-typed; an empty array is not a completed handoff (`game/domain/save_game.gd:68,178,217`, `docs/DECISIONS.md:671-677`).
- `relationships`, `settlements`, `world_changes` and `pending_transactions` have no element schema validation, and lineage-history element shapes are not checked. A future contract needs separate approval (`game/domain/save_game.gd:111-112,213-217`, `game/domain/json_values.gd:28-34`).
- The save validator checks `player.position` length but not each coordinate's numeric finiteness. Conversion later checks more strictly; this is a current validation boundary, not an approved schema change (`game/domain/save_game.gd:113-115`, `game/domain/plane_space.gd:37-43`).
- A same-tick replay after Continue would require a new owner decision and schema work to store live tick, RNG streams and actors. The confirmed contract remains seed regeneration (`docs/DECISIONS.md:671-677`, `game/systems/game_session.gd:177-190`, `game/domain/save_game.gd:40-48`).
