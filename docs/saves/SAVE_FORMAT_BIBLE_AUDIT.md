# Save format versus GENESIS Bible §18 — PROPOSED audit

Status: **PROPOSED documentation audit**, based on `origin/main` commit `9131c575d29185e4182b49db148d372e3c4268a7` (2026-10-24). This does not approve a schema change. Compare the binding [GENESIS Bible §18](../bible/GENESIS_Master_Developer_Bible_v0.1.pdf) with the existing [SAVE_FORMAT.md](SAVE_FORMAT.md), current `SaveGame`, migrations, persistence service and decisions. The [playthrough notes](../research/spore/PLAYTHROUGH_VIDEO_NOTES.md) were read for cross-stage continuity context; they are observational, not save-format authority.

## Resolution (IMPLEMENTED reference update)

The v4 reference update in `SAVE_FORMAT.md` now records all 20 required keys, nested validation rules, both v3 preview migration paths, a loader-checked v4 example and the confirmed seeded-restart limit. The drift described below is retained as the historical audit finding; remaining proposed design gaps are listed at the end of the refreshed reference.

## Immediate documentation drift

`SAVE_FORMAT.md` labels itself **IMPLEMENTED at `f544488`**, calls the on-disk schema **v2 with 15 keys**, and says the only migration is **v1 → v2**. That accurately records an older revision, but is no longer a current reference. `game/domain/save_game.gd` now declares `SCHEMA_VERSION := 4` and 20 required top-level keys; `game/systems/save_migrations.gd` registers 1 → 2, 2 → 3 and 3 → 4. The present v4 writer adds `creature`, `growth`, `checkpoint`, `spawn` and `gen_version`; `player` also carries `energy` and `health`. The document's minimal v2 JSON is valid only as migration input, not as a current writer example. These facts should be added to a **versioned** reference update, retaining the v2 section as history rather than silently relabeling it v4.

The v3 history needs particular care: the creature-lineage save and an S2 cell preview both used v3 during parallel work. `SaveMigrations.v3_to_v4()` fills the missing half; its exact defaults and fixtures should be described, along with the freeze of v4 recorded in `docs/DECISIONS.md` under “Save schema v4.” The old document's “add a field” recipe still points at the v2 constant and one migration; future work must begin at v4 and require an approved v5 migration and fixtures.

| Bible §18 requirement | Current evidence | Missing from `SAVE_FORMAT.md` or remaining gap |
| --- | --- | --- |
| Version, build, seed, lineage, genome, era | `SaveGame.to_dict()` emits them; v4 `KEYS` is exact | Document still says v2 and omits v4 key rules. |
| Generation, discoveries, relationships, settlement records, world changes, position, transactions | `SaveGame` persists these fields; lineage history is separate from genome generation | Document lists them but now misstates the full schema. It should describe current nested shapes and explicitly distinguish placeholder arrays from validated records. |
| Temporary write, validation, safe replace, last-known-good backup | `PersistenceService.save_to()` writes/validates `.tmp`, rotates primary/`.bak`, and leaves errors on failure | Existing transaction explanation remains useful; recheck it against v4 in a refreshed reference. |
| Failed load/migration preserves original and explains failure | `load_from()` tries primary, recoverable temporary and backup; migrations work on a copy | Document omits the v2 → v3 and v3 → v4 branches and their ambiguous preview inputs. |
| Every approved migration has fixtures | `tests/fixtures/save_v1.json`, `save_v2_step2.json`, `save_v3_creature.json`, `save_v3_s2.json` and migration tests exist | List fixtures and expected post-migration v4 fields; add future v5 fixtures only with approved scope. |
| Stable identity independent of filenames | `lineage_id` and genome IDs are serialized within the file; slots choose a path independently | State the invariant and test that moving/renaming a slot does not change IDs. This audit does not claim that such a test currently passes. |
| Separate settings and run state | SaveGame excludes user settings; `SettingsService`/`UserSettings` are separate | Add explicit ownership and reset/backup behavior for the settings file. |
| Era change is a checkpointed transaction | `era` and `pending_transactions` are top-level v4 fields | No approved cross-era transaction record, checkpoint protocol or migration tests are documented or implemented. This remains future design work; an empty array is not a completed handoff. |
| No silent body-part or lineage-history loss | Genome and creature validation reject malformed bodies; history must be nonempty | Add a v4 round-trip assertion for exact body/history survival at every implemented era. Current placeholder relationship/settlement/world arrays validate type, not semantic entries. |

## Continuity limit requiring an explicit decision

The current run save stores world seed and durable lineage/position, **not** the live simulation tick, RNG streams, actor positions, food distribution or pending AI intentions. `GameSession.continue_run()` creates a new `PoolSim`; `SAVE_FORMAT.md` already documents this older restart-on-Continue contract. `docs/DECISIONS.md` records Joshua's 2026-10-24 choice to **keep** that contract after a test review requested exact same-tick continuation. A refreshed format reference should retain that limitation prominently. The Bible's continuity language does not by itself authorize changing the v4 schema or claiming uninterrupted deterministic resume. If future era transitions need stricter continuity, they require an owner decision, explicit checkpoint semantics and fixtures.

## Recommended documentation follow-up, not a schema request

1. Publish a v4 key table and a valid v4 minimal example, with required nested `growth`, `checkpoint`, `spawn`, `player` and optional-empty `creature` shapes. Label the v2 example historical.
2. Draw the v1 → v2 → v3 → v4 migration path, including both v3 preview origins, fixed defaults, failure messages and fixture names.
3. Record which fields are validated structurally and which are only array-typed placeholders; do not suggest that future relationships, settlements or world changes are safely understood already.
4. Specify future era transaction and checkpoint acceptance separately from the current restart-on-Continue behavior. Keep last-known-good recovery and exact lineage/body preservation as gates.

This audit changes no production save behavior, generated fixture, other agent's branch or approved contract. It is a list of reference gaps for owner/studio review.
