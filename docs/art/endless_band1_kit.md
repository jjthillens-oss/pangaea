# Endless world band-1 art kit and S3 extras (PROPOSED)

This is the band-1 art for the endless cell world and the S3 extras from section I of
the earlier endless-cell plan. The kit is built to the same art contract as band 0
(`docs/art/endless_s1_kit.md`): bounds, swim-band outline, heights, triangle budgets, node names,
growth children and colours clear of the food and threat hues.

The pieces come from `tools/blender/make_s3_kit.py`, which reuses the band-0 builders and
`make_s1_production.finish` to bake one texture set per piece (albedo detail, ORM, normal). Run it
with `--rough` for a fast contract check without the bake. Every record carries `"band": 1`.
The pieces are not yet in `game/data/placement_kit.json`; they go in once engineering's S3
placement spec names their groups and spawn rules. Review sheets are in
`docs/art/renders/production/<id>_sheet.jpg`. Joshua judges the look.

| Id | Kind | Triangles | Notes |
|---|---|---|---|
| `shell_b1_lattice_cap` | Shell, `fp_s` | 1,200 | A glass drum under a low lattice cap |
| `shell_b1_tiered_disc` | Shell, `fp_s` | 1,240 | A stepped, scalloped glass disc with an amber core |
| `shell_b1_rimmed_cup` | Shell, `fp_m` | 1,256 | An open glass cup with a rolled lip, a lavender pearl inside |
| `shell_b1_spined_drum` | Shell, `fp_m` | 1,040 | A frosted drum with a star of glass spines on its crown |
| `shell_b1_glass_dome` | Shell, `fp_l` | 1,248 | A broad ribbed glass dome ringed with lavender pores |
| `landmark_b1_sponge_tower` | Landmark, group 0 | 3,776 | A glass-sponge basket rising from its drum, glowing inside |
| `landmark_b1_coccolith_stack` | Landmark, group 0 | 4,760 | Overlapping coccolith plates turning as they rise |
| `landmark_b1_heliozoan` | Landmark, group 1 | 3,708 | A sun-animalcule's empty glass test bristling with fine spines |
| `landmark_b1_foram_spiral` | Landmark, group 1 | 4,448 | A foraminifer's chambered test climbing in a spiral |
| `landmark_b1_diatom_chain` | Landmark, group 2 | 4,944 | A zig-zag chain of diatom drums joined valve to valve |
| `landmark_b1_bell_colony` | Landmark, group 3 | 5,448 | Lavender bells on six coiled cream stalks |
| `rare_sunbeam_well` | Rare | 6,864 | Six crowned glass pillars round a deep well where a sunbeam lands |
| `rare_fallen_lattice` | Rare | 2,612 | A giant radiolarian lattice, fallen and half sunk, one side broken open |
| `rare_sponge_grove` | Rare | 7,960 | A grove of lattice-walled glass-sponge vases glowing amber inside |
| `rare_shed_shell` | Rare | 3,200 | A giant foraminifer's empty chambered test on its side, broken open |

Budgets: shells 1,300, landmarks 6,000, rare pieces 12,000. Every landmark has the plain, frosted and
amber dressings, as in band 0.

## S3 extras (`tools/blender/make_endless_extras.py`)

| Id | Triangles | Notes |
|---|---|---|
| `veil_threads` | 1,344 | The veil's thread rig. Engine-drawn: UV v runs root to tip and a `ThreadWeight` vertex colour drives the sway. Two materials, `M_VeilThreadInk.tres` and `M_VeilThreadNeutral.tres`, keep it readable at 14 tm in the ink and neutral looks |
| `cradle_ring` | 3,456 | Radius 7 m, top at -1.6 m, below the swim band |
| `home_beacon` | 2,244 | Crown at -16.2 m, deep under the plane so it reads as a far glow |
| `ghost_engulfer`, `ghost_lancer` | render-only | Rough size-5 and size-6 models; only their ghost billboards ship |

`assets/export/ambience/T_BloomTint.png` is a soft round gradient, white to clear, that the engine
tints #E8D27A over a blooming meadow. It and the size-5 and size-6 ghosts
(`T_Ghost_engulfer.png`, `T_Ghost_lancer.png`) are recorded in
`assets/records/sprites/endless_sprites.json`.

Still to come: the Lurker's second-lair dressing, once engineering's S2 build plan gives its
placement. The cell stage is microscopic, so nothing here has bones or skeletons.
