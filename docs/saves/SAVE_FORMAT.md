# Save format reference

Status: **IMPLEMENTED** at base commit `f544488`. This describes the current schema and loader; changing the schema requires owner approval (`CLAUDE.md:10`). All paths and line numbers below refer to that base commit.

## Files and transactions

The title screen offers three slots, `user://saves/slot_1.json` through `slot_3.json`; the number passed to `SaveSlots.path()` is clamped to 1–3. Slot 1 is the earlier default, and `SaveSlots.folder` can be redirected by tests (`game/systems/save_slots.gd:3-16`, `game/systems/game_session.gd:17`, `tests/save_folder.gd:9-17`). On Windows, the default is under `%APPDATA%\Pangaea\saves` (`game/systems/game_session.gd:17`).

`PersistenceService.save_to()` validates the in-memory `SaveGame`, stamps `saved_at_unix`, writes `<slot>.tmp`, and re-reads it with the normal loader. A valid existing primary is renamed to `<slot>.bak` before the verified temporary file becomes primary. An invalid primary is renamed to `<slot>.corrupt-<unix time>` while its prior backup is retained. Failed/refused writes remove the temporary file; errors are returned rather than reporting success (`game/systems/persistence_service.gd:28-70`). This is a rename transaction, not an in-place overwrite (`game/systems/persistence_service.gd:50-70`).

`load_from()` tries primary, then a valid `.tmp` only if primary is absent, then `.bak`. The recovered `.tmp` case handles interruption between the two renames. It does not change files; if all candidates fail it returns `ok=false` with accumulated errors. Parse failure, invalid schema, invalid data and newer versions produce explanatory errors (`game/systems/persistence_service.gd:73-143`, `tests/test_persistence.gd:116-151`). Corrupt primary files survive a read and are set aside on the next successful write (`tests/test_persistence.gd:116-140`).

## JSON schema, version 2

The writer emits the 15 keys below. The loader expects each typed key: missing or wrong-typed values add a load problem and fail validation rather than silently defaulting (`game/domain/save_game.gd:69-109`, `game/domain/json_values.gd:3-42`, `tests/test_game_session.gd:8-11`). JSON whole numbers may parse as floats, but only finite integral values are accepted (`game/domain/json_values.gd:9-17`).

| Key | JSON type and meaning | Validation or unit |
| --- | --- | --- |
| `schema_version` | Whole number, currently `2` | Migrated/refused before decoding; newer versions are refused (`game/domain/save_game.gd:7,71`, `game/systems/persistence_service.gd:120-137`). |
| `build_id` | String identifying build | Typed, with no further content check (`game/domain/save_game.gd:13,72,94`, `game/domain/json_values.gd:20-25`). |
| `world_seed` | Whole-number world seed | 0 through 2^53 inclusive so JSON preserves it exactly (`game/domain/save_game.gd:8-9,51-54,73`, `tests/test_persistence.gd:280-290`). |
| `lineage_id` | String `lineage_` plus 16 hex digits | Must pass stable-id check (`game/domain/save_game.gd:15,45-46,74`, `game/domain/stable_id.gd:12-16`). |
| `era` | String era identifier | One of the seven strings in `SaveGame.ERAS` (`game/domain/save_game.gd:10-11,47-48,75`). |
| `genome` | Object described below | Required and validated against the part catalog; its lineage must match (`game/domain/save_game.gd:55-60,76,98-99`). |
| `adaptation_points` | Whole number of unspent points | Non-negative; added in v2 (`game/domain/save_game.gd:18-19,49-50,77`, `game/systems/save_migrations.gd:13-17`). |
| `lineage_history` | Ordered array of event objects | Nonempty; founding event contains `generation`, `genome_id`, `event`. Later birth/death events may carry more keys (`game/domain/save_game.gd:20-21,39,61-62,78`, `game/domain/lineage.gd:87-91,119-126`). |
| `discoveries` | Array | Type checked; element schema is not checked here (`game/domain/save_game.gd:22,79,102`, `game/domain/json_values.gd:28-34`). |
| `relationships` | Array | Type checked; element schema is not checked here (`game/domain/save_game.gd:23,80,103`, `game/domain/json_values.gd:28-34`). |
| `settlements` | Array | Type checked; element schema is not checked here (`game/domain/save_game.gd:24,81,104`, `game/domain/json_values.gd:28-34`). |
| `world_changes` | Array | Type checked; element schema is not checked here (`game/domain/save_game.gd:25,82,105`, `game/domain/json_values.gd:28-34`). |
| `player` | Object with `position` array | Exactly three entries are required; normal writer uses world `[x, y, z]` metres with swim `y=0`, mapping plane `[x, y]` to world `[x, 0, z]` (`game/domain/save_game.gd:26,63-66,83,106`, `game/domain/plane_space.gd:3-6,28-43`). |
| `pending_transactions` | Array | Type checked; element schema is not checked here (`game/domain/save_game.gd:27,84,107`, `game/domain/json_values.gd:28-34`). |
| `saved_at_unix` | Whole-number Unix timestamp in seconds | Set from system time on write; no range check on load (`game/domain/save_game.gd:28,85,108`, `game/systems/persistence_service.gd:33`). |

The nested `genome` writer emits `schema_version: 1`, `genome_id`, `lineage_id`, `parent_genome_id` (strings), `generation` (whole number at least 1), `appearance` (object), `parts` (array) and `next_part_number` (whole number used for new part IDs). IDs use 16 hex digits; parts have string `id`/`type`, angle in radians from −π to π, and catalog-bounded scale. The catalog currently limits parts to eight, requires a mouth, and sets scale to 0.5–2.0 (`game/domain/genome.gd:6-15,50-103`, `game/domain/stable_id.gd:12-16`, `game/data/part_catalog.json:5-11`). `next_part_number` may be reconstructed from part IDs when absent or nonpositive; other missing/wrong-typed nested fields are recorded as problems (`game/domain/genome.gd:107-132`).

### Complete minimal v2 example

This example has the required mouth and propulsion parts, a founding lineage event and every top-level key. It uses the valid IDs and parts from the v1 migration fixture, with v2's adaptation points added (`tests/fixtures/save_v1.json:1-28`, `game/systems/save_migrations.gd:13-17`, `game/data/part_catalog.json:5-11`).

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

## Migration and determinism

The current version is 2. The only registered migration is 1 → 2: it sets `adaptation_points` to zero and updates `schema_version`, preserving other fields. Migration works on a deep copy in memory; reading an old file does not rewrite it. Schema 0 has no registered production migration, and a version newer than 2 is refused (`game/domain/save_game.gd:7`, `game/systems/save_migrations.gd:3-17`, `game/systems/persistence_service.gd:120-137`, `tests/test_persistence.gd:202-216`).

The running simulation uses seeded RNG streams and integer 60 Hz ticks; `PoolSim.snapshot()` includes tick and stream states and hashes a stable JSON snapshot (`game/systems/pool_sim.gd:35,72,247-292`, `tests/test_sim_purity.gd:1-20,84-93`). Simulation vector snapshots use `[x, y]` pairs and deterministic creature iteration/order (`CLAUDE.md:15`, `game/systems/pool_sim.gd:13-35`). **The v2 disk save does not contain the running tick or RNG stream states:** its 15 keys include `world_seed` and persistent lineage/position, while Continue creates a fresh `PoolSim` from them. The approved design explicitly restarts the world from seed and repopulates creatures; save/continue does not promise tick-for-tick continuation of the prior live simulation (`game/domain/save_game.gd:69-86`, `game/systems/game_session.gd:3-7,137-150`, `docs/DECISIONS.md:60,111`).

## Slot behavior and adding a field

`SaveSlots.peek_all()` reads each of the three slots in order. `peek_slot()` reports existence, validity, source, errors and a summary containing lineage ID/tag, starting-body label, generation, points, save time, seed and the decoded genome. It calls the full loader, but does not write or start the pool; there is no separate header-only read. The UI can present a card without continuing the run (`game/systems/save_slots.gd:27-43`, `game/systems/game_session.gd:83-108`, `tests/test_game_session.gd:117-140`). Deletion removes primary, `.bak` and `.tmp` but retains `.corrupt-*` files. Starting a new lineage over a good slot moves the old save to backup (`game/systems/save_slots.gd:45-55`, `tests/test_game_session.gd:142-154`).

To add a field after owner approval: advance `SaveGame.SCHEMA_VERSION` and its writer/reader/validation; register a one-step migration keyed by the old version in `SaveMigrations.all()`; give old saves an explicit value and advance their `schema_version`; add an old-version fixture and load/round-trip tests, including the exact top-level-key assertion; then exercise primary, backup and corrupt-file cases (`CLAUDE.md:10`, `game/domain/save_game.gd:7,43-109`, `game/systems/save_migrations.gd:3-17`, `game/systems/persistence_service.gd:120-137`, `tests/test_persistence.gd:202-216`, `tests/test_game_session.gd:8-11,79-91`).

## Gaps for studio review (PROPOSED)

- Element shapes in `discoveries`, `relationships`, `settlements`, `world_changes` and `pending_transactions` are not validated by `SaveGame.validate()`; only their array types are checked, so consumers must interpret their contents (`game/domain/save_game.gd:43-66,101-108`, `game/domain/json_values.gd:28-34`).
- `SaveGame.validate()` checks `player.position` length but not that each coordinate is numeric and finite; `PlaneSpace.from_save()` does perform that stricter check when converting it (`game/domain/save_game.gd:63-66`, `game/domain/plane_space.gd:37-43`).
- v2 does not persist live tick/RNG/creature state, so a same-tick resumed hash cannot match an uninterrupted run under the approved restart-on-Continue design. A future change would require an owner-approved schema decision (`game/domain/save_game.gd:69-86`, `game/systems/game_session.gd:137-150`, `docs/DECISIONS.md:60,111`).

