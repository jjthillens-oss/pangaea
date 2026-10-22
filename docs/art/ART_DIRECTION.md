# Pangaea art direction (draft)

**Status: PROPOSED.** Nothing here is an approved art style until Joshua approves the look
(Bible section 15: passing needs owner approval of the benchmark; scores cannot authorize a
style). Gameplay placeholders stay in place until then.

Sources: Bible sections 2, 15 and 16. Spore (2008) is the fidelity bar, not a reference library:
no Spore shapes, palettes, UI or names are copied, and none of the files below were made by
looking at Spore assets.

## 1. The idea in one line

**"Soft life hardens."** Every era is told through what living things are made of. The
microscopic era is jelly and light, the aquatic era adds cartilage and scale, land brings
bone and hide, the social and tribal eras bring woven and carved things, civilization brings
fired and cast materials, and the interstellar era ends in polished alloy and glass. The player
should be able to tell the era from a silhouette and a material sphere alone. This also gives
each era its own look without starting a new style every time.

## 2. Shape language

| Rule | What it means in practice |
| --- | --- |
| **Pebble, petal, bead** | Every creature is one *pebble* (the soft main mass, weight sitting low), a few *petals* (lips, lids, fins, frills that taper to a soft point) and a scatter of *beads* (eyes, nodules, organelles). |
| **60 / 30 / 10** | About 60% of the silhouette is the pebble, 30% petals, 10% beads. If beads start reading at gameplay distance as noise, remove them. |
| **One clear front** | The face sits on the front third and points where the creature swims (Blender +Y, Godot -Z). Eyes are big: 18 to 25% of body width. |
| **Lids before pupils** | Emotion comes from eyelids and body squash, not from pupil size. Every eye gets a lid so the rig can show attention, fear, effort and satisfaction (Bible section 21). |
| **No perfect symmetry** | Bodies get a small, deliberate lean or bulge (2 to 5% of size). Paired parts stay mirrored so the editor still works. |
| **Soft era, soft edges** | In the microscopic era there are no hard bevels or sharp corners. Spikes are the one exception, because a sharp shape must mean danger. Hardness increases era by era (section 1). |
| **Silhouette test** | At the gameplay camera (55 degree pitch, 45 degree FOV, 14 m) the creature must be identifiable as a black shape about 90 px tall at 1080p. Each rung of the quality ladder ships with this render. |

## 3. Palette

Values are a starting board, PROPOSED. Swatches: `docs/art/renders/palette.png`; material spheres (left to right: clay, membrane, teal membrane, organelle, eye, lid and lip, food, threat): `docs/art/renders/material_sheet.jpg`. Both come from `tools/blender/render_material_sheet.py`. Habitats are cool and slightly desaturated; living
things and anything interactive are warmer and more saturated, so they read against the
background before detail does. Color is never the only signal (Bible section 20): food, threat
and mate also differ in shape and motion.

| Role | Hex | Use |
| --- | --- | --- |
| Deep shadow | `#1D3557` | Pool depths, ambient shadow color. Shadows go blue, never black. |
| Pool teal | `#2A7F86` | Water tint, far habitat. |
| Shallow turquoise | `#49B3A6` | Lit habitat surfaces. |
| Algae green | `#6BAB5A` | Plants and grazer-friendly zones. |
| Moss deep | `#2F6B4A` | Habitat mid-tones. |
| Cream highlight | `#F4EAD2` | Speculars, belly gradient, eye whites. Never pure white. |
| Mineral amber | `#E3A64A` | Warm accents, rocks in light, nucleus glow. |
| Coral (player default) | `#E9744F` | Default player membrane. Players can recolor; this is the starting look. |
| Rust | `#A94F3A` | Pattern marks, lips, darker side of warm bodies. |
| Food glow | `#CFE86A` | Plankton and anything edible: the only yellow-green that glows. |
| Threat | `#D9466B` | Spikes and attack tells. Always paired with a sharp shape. |
| Clay | `#B9B3A8` | Neutral clay renders (Bible section 15 asks for clay next to beauty). |

Saturation discipline: habitat colors stay below about 55% saturation, creature colors may go
to about 75%, and only food and threat may exceed that.

## 4. Materials

Materials must survive the trip from Blender to Godot, so they use only what glTF carries and
Godot imports: base color, roughness, metallic, normal, emission and (for the eye cornea)
alpha. Translucency is faked with a painted gradient and a light rim in the albedo rather than
real subsurface or transmission, which glTF export and Godot's renderers handle differently.

| Family | Look | Base settings (Principled BSDF) | Era |
| --- | --- | --- | --- |
| **Membrane** | Soft, slightly waxy, gradient darker on the back, cream on the belly, faint rim | roughness 0.45 to 0.55, metallic 0, baked albedo gradient | 1 to 2 |
| **Organelle** | Glows faintly through the body | emission 0.3 to 0.8, roughness 0.6 | 1 |
| **Eye** | Wet, glossy cornea over a painted iris | cornea roughness 0.05, iris roughness 0.4 | all |
| **Lid and lip** | Matte, a shade darker than the body | roughness 0.65 | all |
| **Cilia and flagella** | Thin, lighter tip | roughness 0.5, albedo gradient root to tip | 1 to 2 |
| Later families | Scale, chitin, hide, bone, woven fibre, fired clay, alloy | to be written with each era | 2 to 7 |

Textures: one albedo and one ORM (occlusion, roughness, metallic) per creature, 512 px for
microscopic creatures and 1024 to 2048 px for prominent ones (Bible section 16 budgets).
Albedo is sRGB; ORM and normal maps are linear (non-color). Textures are painted or baked in
Blender from procedural nodes. No photo textures and no AI-generated images.

Clay renders use one material (`#B9B3A8`, roughness 0.6) so form can be judged apart from
color and lighting.

## 5. Scale

1 Blender meter = 1 Godot unit (CONFIRMED in M0). The game world is not real size: the
microscopic tide pool is about 80 m across in game units.

| Class | Size in game units | Examples |
| --- | --- | --- |
| Cell-stage creature | 0.8 to 2.0 m long | player cell, hunters, rammers |
| Food and particles | 0.15 to 0.5 m | plankton, carrion chunks |
| Pool props | 1 to 6 m | rocks, vents, plants |
| Habitat | about 80 m across | the M1 tide pool |

Later eras set their own scale, keeping a typical player creature at 1 to 2 m so cameras and
rigs carry over. A scale lineup render is part of the M2 reference package.

## 6. Lighting for reviews

Turntables use one setup so rungs and assets compare fairly: a warm key light from the
front-left above, a cool fill from the right, a teal rim from behind, and a soft blue-grey
world. Shadows stay readable and tinted blue. Each review sheet shows clay and beauty side by
side, plus the gameplay-camera silhouette.

## 7. The quality ladder

Every asset climbs the same rungs, each owned by one art role and each checked before the
next starts. The demo in `docs/art/quality_ladder.md` takes one cell through all four.

| Rung | Owner | Done when |
| --- | --- | --- |
| 0 Blockout | Modeler | Proportions and silhouette read at gameplay distance. Clay only. |
| 1 Form | Modeler | Clean topology, petals and beads in place, sockets kept. Clay still reads well. |
| 2 Surfaced | Surfacing | UVs, baked albedo and ORM, palette applied, glTF-safe materials. |
| 3 Target | Rigging and animation, then technical artist | Armature, idle and swim cycles, triangle budget met, GLB checked in Godot. |
