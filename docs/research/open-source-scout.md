# Open-source and license scout

**Status:** PROPOSED research; adopting any dependency needs owner approval (CLAUDE.md).
**Date:** 2026-10-22
**Pinned context:** Godot 4.7.2-stable (GDScript, standard build), Blender 5.2.2 LTS. See `docs/TOOLCHAIN.md`.

## Method

- Scope: things Pangaea could legally use or learn from. Permissive licenses only for anything that ships
  or enters the repo: MIT, BSD-2-Clause, BSD-3-Clause, Apache-2.0, Zlib, MPL-2.0 (weak copyleft, file-level),
  CC0-1.0, CC-BY-4.0 (attribution). GPL, LGPL, AGPL, CC-BY-SA and any NC license are reference-only.
- Each license was checked on the project's own repository page or license file on 2026-10-22 (GitHub repo
  sidebar, `LICENSE` file, or the site's license page). Blog posts were used only for technique summaries.
- Limits of this pass: the GitHub API was not reachable from this session, so "last activity" comes from
  each repository's Releases page. GitHub showed day and month but often no year; where the release notes
  name Godot 4.7 the year is clearly 2026 and that is marked "(2026, inferred)". Other dates are shown as
  given. No add-on was installed or run in our project; "Godot 4.x compatible" is what the project says
  about itself, not something we tested on 4.7.2.
- Rows marked **UNVERIFIED** were not confirmed from a primary source in this pass.
- Bible constraints applied (sections 12, 15, 16, 17, and the agent rules):
  every production mesh, rig and authored animation needs an editable Blender source; runtime
  deformation, terrain assembly and procedural placement need an approved boundary naming which
  Blender-authored sources they use; no new dependencies, paid services, runtime AI or network calls
  without approval; no imported art packs as routine choices.

## License log

Recommendation key: **Adopt-candidate** (permissive, fits, worth asking the owner to approve),
**Reimplement-from-idea** (learn the technique, write our own code), **Reference-only** (copyleft or
otherwise unsuitable to copy), **Avoid** (wrong fit or risk). "Built-in" means already part of Godot
4.7.2 or Blender 5.2.2, so it is not a new dependency.

| Name | Category | URL | License (SPDX) | Verified from | Godot 4.x? | Last activity | Fit for GENESIS | Risk notes | Recommendation |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Godot Engine | Engine | https://github.com/godotengine/godot | MIT | https://github.com/godotengine/godot/blob/master/LICENSE.txt | Is Godot | 4.7.2 pinned | Everything | Already in use. Keep its notice in credits. | Built-in |
| Godot IK framework (IKModifier3D, TwoBoneIK3D, FABRIK3D, CCDIK3D, JacobianIK3D, SplineIK3D) | IK | https://godotengine.org/article/inverse-kinematics-returns-to-godot-4-6/ | MIT (part of Godot) | Godot LICENSE.txt | Added in 4.6 | Article 2025-12-16 | Legs, fins, grasping, head aim from M2 on | 4.6 release page says "Documentation is in the works". Test on 4.7.2 before relying on it. | Built-in, use first |
| LookAtModifier3D, SpringBoneSimulator3D, BoneConstraint3D (+ Aim/CopyTransform/ConvertTransform), LimitAngularVelocityModifier3D, BoneTwistDisperser3D | Procedural animation | same article; https://godotengine.org/releases/4.5/ | MIT (part of Godot) | Godot LICENSE.txt | 4.4 to 4.6 | as above | Eye/head attention (Bible 15), tail and antenna wobble, smoothing IK | None beyond testing. | Built-in, use first |
| SkeletonIK3D | IK | https://docs.godotengine.org/en/latest/classes/class_skeletonik3d.html | MIT (part of Godot) | Godot LICENSE.txt | Present but deprecated | n/a | None | Docs say "Deprecated: may be changed or removed". | Avoid |
| Jolt Physics (engine module) | Physics | https://godotengine.org/releases/4.6/ | MIT | https://github.com/godotengine/godot/blob/master/thirdparty/README.md (Jolt 5.6.0, MIT) | Built in since 4.4; default for new 3D projects since 4.6 | n/a | Creature bodies, collision proxies | Our `project.godot` sets no physics engine, so it likely still uses Godot Physics. Switching is a project decision; test first. | Built-in, decide later |
| Godot Jolt (GDExtension) | Physics | https://github.com/godot-jolt/godot-jolt | MIT | repo page ("distributed under the MIT license") | 4.x | Maintenance mode; to be archived once engine module matches | None: superseded | Extra dependency for no gain. | Avoid |
| Godot LOD generation | Pipeline | https://godotengine.org/releases/4.6/ | MIT (uses meshoptimizer 1.2, MIT, per thirdparty README) | Godot thirdparty/README.md | Built in | 4.6 improved shape preservation | Automatic LODs on import of our GLBs | Must still pass the Bible "LOD keeps silhouette" check. | Built-in, use first |
| AccessKit (screen reader support) | Accessibility | https://godotengine.org/releases/4.5/ | MIT (accesskit-c 0.22.3) | Godot thirdparty/README.md | Built in since 4.5, "experimental" | n/a | Menus, editor, settings UI | Control nodes only; custom nodes need bindings. | Built-in, use first |
| GUT | Testing | https://github.com/bitwes/Gut | MIT | repo page; license in `addons/gut/LICENSE.md` | 9.7.1 targets 4.7.x | v9.7.1, 10 Jul (2026, inferred) | Not needed: we have `tests/run_tests.gd` | Would duplicate our runner. | Reference-only (by choice) |
| gdUnit4 | Testing | https://github.com/MikeSchulze/gdUnit4 | MIT | repo sidebar + LICENSE file | v6.2.x: 4.5 to 4.7.1; v7 (master): 4.7+ | v6.2.2, 07 Oct (2026, inferred) | Scene/input test helpers if our runner hits limits | Same as above; adds CI complexity. | Reference-only (by choice) |
| Dialogue Manager | UI/narrative | https://github.com/nathanhoad/godot_dialogue_manager | MIT | repo page ("Licensed under the MIT license") | v4.x: Godot 4.6+ | v4.1.0 for 4.7, 04 Sep (2026, inferred) | Tribal/civilization diplomacy text, tutorials (later eras) | Not needed for M1/M2. | Adopt-candidate (later era) |
| Phantom Camera | Camera | https://github.com/ramokz/phantom-camera | MIT | repo sidebar + LICENSE file | 4.4+ | v0.11.0.3 (fix for 4.7.1), 19 Jul (2026, inferred) | Follow/framing camera, editor orbit camera | Pre-1.0; our M1 camera rule (55 degree tilt, one plane) is simple to write ourselves. | Adopt-candidate (only if camera work grows) |
| Terrain3D | Terrain | https://github.com/TokisanGames/Terrain3D | MIT | repo page ("released under the MIT License") | 4.4 to 4.6+; 4.7 not stated | v1.0.2-stable, 19 May | Land eras (creature onward) heightmap terrain | C++ GDExtension; not stated for 4.7. Bible: terrain surface assets need Blender sources and runtime terrain assembly needs an approved boundary. | Adopt-candidate (M3+, after 4.7 test) |
| Spatial Gardener | Scatter | https://github.com/dreadpon/godot_spatial_gardener | MIT | repo sidebar (LICENSE.md) | 4.2+ | No release date visible | Hand-painted plant placement | Activity unclear. Placement of Blender-authored plants is "procedural placement" and needs an approved boundary. | Reference-only until activity checked |
| ProtonScatter | Scatter | https://github.com/HungryProton/scatter | MIT | repo page ("published under the MIT license") | Godot 4 | No release date visible (GitHub is a Codeberg mirror) | Rule-based scatter of rocks/plants | Same boundary note; check Codeberg for activity. README says most bundled demo textures come from Textures.com (not CC0, not redistributable on their own): never ship or commit those textures. | Adopt-candidate (M2 habitat, after check) |
| Beehave | AI | https://github.com/bitbrain/beehave | MIT | repo sidebar + LICENSE file | 2.10+ for 4.5+ (table) | v2.9.3, 18 Aug (year not shown) | Behavior trees for idle/forage/flee etc. (Bible 13) | Release list and version table disagree (2.10+ listed, 2.9.3 latest); check before use. GDScript only. | Reimplement-from-idea (M1 states are few) |
| LimboAI | AI | https://github.com/limbonaut/limboai | MIT (repo says "MIT-style"; demo art CC-BY-4.0) | repo page + LICENSE file | GDExtension for 4.6+; module for 4.7 | v1.8.1, 2026-08-20 | Behavior trees + hierarchical state machines with editor and debugger (Bible 13 AI states) | C++ GDExtension is labelled 4.6 for the extension build; test on 4.7.2. Do not ship its CC-BY demo art. | Adopt-candidate (when AI outgrows hand-written states) |
| Debug Draw 3D | Debug | https://github.com/DmitriySalnikov/godot_debug_draw_3d | MIT | https://github.com/DmitriySalnikov/godot_debug_draw_3d/blob/master/addons/debug_draw_3d/LICENSE | Godot 4 (GDExtension, C++) | No release date visible | Drawing perception cones, IK targets, foot rays | Native binary; keep out of release exports. | Adopt-candidate (dev-only) |
| Godot Input Helper | Input | https://github.com/nathanhoad/godot_input_helper | MIT | repo page ("Licensed under the MIT license") | Godot 4 | No date visible | Device detection, rebinding helpers | Godot's InputMap already covers remapping; small benefit. | Reimplement-from-idea |
| Many Bone IK | IK | https://github.com/V-Sekai/many_bone_ik | MIT | https://github.com/V-Sekai/many_bone_ik/blob/main/LICENSE | Engine module (SCons, needs custom Godot build) | No date visible | Full-body IK with joint limits | Needs a custom engine build; breaks our "official standard build" pin. | Avoid (reference the ideas) |
| GodotIK (monxa) | IK | https://github.com/monxa/GodotIK | MIT | repo sidebar (MIT license file) | 4.3+ (GDExtension) | No release date visible | FABRIK with constraints | Godot 4.6+ now has built-in FABRIK3D. | Avoid (superseded) |
| godot_voxel | Meshing | https://github.com/Zylann/godot_voxel | MIT | repo sidebar (MIT license) | Godot 4 (module; GDExtension "incomplete") | No date visible | Smooth (Transvoxel) terrain, caves | Custom build likely; production meshes must stay Blender-authored. | Reference-only (by choice) |
| godot-marching-cubes (gharielsl) | Meshing | https://github.com/gharielsl/godot-marching-cubes | MIT (per Asset Library entry) | https://www.godotengine.org/asset-library/asset/edit/15061 | Godot 4.1 | No date visible | Example of marching cubes in GDScript | Voxel game demo, not creature tool; repo LICENSE itself not opened. | Reference-only |
| glTF-Blender-IO (Blender glTF exporter) | Pipeline | https://github.com/KhronosGroup/glTF-Blender-IO | Apache-2.0 | repo sidebar (LICENSE.txt) | n/a | Bundled with Blender | Our GLB export path | Already bundled with Blender; README lists 5.0 as current, so its notes may lag 5.2.2. | Built-in |
| glTF-Validator (Khronos) | Pipeline | https://github.com/KhronosGroup/glTF-Validator | Apache-2.0 | repo sidebar (LICENSE file) | n/a (CLI) | v2.0.0-dev.3.10, 22 Oct (year not shown), prebuilt packages attached | CI check of every exported GLB before Godot import | Dev tool only; never shipped. Pre-release "dev" versioning. | Adopt-candidate (CI tool) |
| meshoptimizer / gltfpack | Pipeline | https://github.com/zeux/meshoptimizer | MIT | repo sidebar (LICENSE.md); Godot thirdparty README also lists it as MIT | n/a (CLI) | v1.2, 30 Jun | Offline LOD/simplification experiments (`-si`), mesh stats | Default output uses quantization/compression extensions; Godot import support for those is UNVERIFIED, so use `-noq` and no `-c`. Godot's built-in LOD already uses meshoptimizer. LOD meshes must still go back through Blender for review. | Reference-only (by choice); Adopt-candidate only if Godot LODs fail review |
| Blender metaballs, Skin modifier, Mesh to Volume / Volume to Mesh, Geometry Nodes SDF Grid nodes | Creature meshes | https://docs.blender.org/manual/en/5.2/modeling/geometry_nodes/volume/operations/sdf_grid_boolean.html | GPL-2.0-or-later (Blender itself) | Blender is GPL; output files are ours | n/a (authoring) | 5.2 LTS manual lists SDF Grid Boolean | Blobby body blockouts and base meshes, authored in Blender | Using Blender to author does not make our assets GPL. Copying Blender's C/C++ or Python add-on code into the game would. | Built-in (authoring only) |
| Poly Haven | Assets | https://polyhaven.com | CC0-1.0 | https://polyhaven.com/license | n/a | n/a | HDRIs for lighting tests, texture reference | CC0 covers assets only; logos, renders and site text excluded; no scraping. 3D models need approval and Blender finalisation. | Adopt-candidate (HDRIs, textures) |
| ambientCG | Assets | https://ambientcg.com | CC0-1.0 | https://docs.ambientcg.com/license/ | n/a | n/a | PBR textures for rock/sand material studies | Photoreal noise conflicts with Bible 15 style; use as base, repaint in Blender. | Adopt-candidate (textures) |
| Kenney | Assets | https://kenney.nl | CC0-1.0 | https://kenney.nl/support | n/a | n/a | UI icons, placeholder audio, prototyping | Logo reserved. Style differs from ours; Bible forbids imported art packs as routine. | Reference-only for 3D; Adopt-candidate for placeholder UI/audio |
| Freesound | Audio | https://freesound.org | Per sound: CC0-1.0, CC-BY-4.0, CC-BY-NC (and legacy Sampling+) | https://freesound.org/help/faq/ | n/a | n/a | M1 placeholder audio, Foley sources | License is per sound. Accept only CC0 or CC-BY (record credit); reject NC and Sampling+. | Adopt-candidate (CC0/CC-BY only, per file) |
| OpenGameArt | Assets/audio | https://opengameart.org | Per asset: CC0, CC-BY 3.0/4.0, CC-BY-SA, OGA-BY, GPL | https://opengameart.org/content/faq | n/a | n/a | Occasional audio/texture | Many items are SA or GPL; provenance varies. | Reference-only unless CC0 and provenance clear |
| Thrive | Game (reference) | https://github.com/Revolutionary-Games/Thrive | GPL-3.0-or-later (with a mod-linking exception) | https://github.com/Revolutionary-Games/Thrive/blob/master/LICENSE.txt | Godot, C# | Thrive 1.6.0, 30 Aug | Design reference only (see below) | Asset license not stated in LICENSE.txt or README; treat all of it as copyleft. | Reference-only |

### Research and algorithms (public design knowledge; we write our own code)

| Work | What it gives us | Verified from | Recommendation |
| --- | --- | --- | --- |
| Hecker, Raabe, Enslow, DeWeese, Maynard et al., "Real-time motion retargeting to highly varied user-created morphologies", SIGGRAPH 2008 (Spore) | Animations stored independent of skeleton, mapped at runtime to pose targets for an IK solver. Core idea for rig families + gait templates (Bible 12). | https://history.siggraph.org/?p=112832 (author's page chrishecker.com was down on 2026-10-22) | Reimplement-from-idea |
| Chris Hecker, "How To Animate a Character You've Never Seen Before" (talk) | Same topic, practitioner level. | Title only, via chrishecker.com search result; page was down. **UNVERIFIED** venue/year. | Reimplement-from-idea |
| Aristidou & Lasenby, "FABRIK: a fast, iterative solver for the inverse kinematics problem", Graphical Models 73(5), 2011, DOI 10.1016/j.gmod.2011.05.003 | The solver behind Godot's FABRIK3D; useful to understand limits and tuning. | https://www.andreasaristidou.com/FABRIK | Reimplement-from-idea (or just use FABRIK3D) |
| Procedural leg stepping pattern (raycast foot targets, step when the planned foot spot drifts past a threshold, arc the foot, alternate diagonal pairs, body height/tilt from feet) | Gait for arbitrary leg counts. | https://80.lv/articles/ik-driven-procedural-spider-locomotion-in-godot-4-5 (2025-12-17; source code license not stated) | Reimplement-from-idea |
| Metaballs / scalar fields + marching cubes (Blinn 1982; Lorensen & Cline 1987) | Blobby, Spore-like bodies from spheres and capsules; offline in Blender or as a runtime preview. | Technique summary from https://forum.godotengine.org/t/metaballs-for-mesh-generation-spore-creature-creator/92992; original paper citations **UNVERIFIED** in this pass | Reimplement-from-idea (with care, see 1) |
| B-Mesh (Ji, Liu, Wang, 2010), basis of Blender's Skin modifier | Base meshes from a skeleton of spheres; good for limbs and tails. | **UNVERIFIED** citation (Blender manual page fetched without body text) | Reimplement-from-idea / use Blender Skin modifier |

## Per-category notes

### 1. Procedural creature meshes

- No permissively licensed, maintained Godot 4 add-on for creature-style metaball or SDF body
  generation was found. What exists is terrain-oriented (godot_voxel, marching cubes demos) or shader
  raymarching (not a mesh, so it cannot satisfy the Blender-source rule).
- The Bible makes the real question one of approval, not licensing: runtime deformation may only
  operate on Blender-authored meshes, and procedural assembly needs an approved boundary.
- Realistic path, in order of fit:
  1. **Blender-authored parts plus shape keys (glTF morph targets).** Author each part and body
     segment in Blender with shape keys for fat/thin/long/short; Godot drives blend weights at runtime.
     Nothing new to install, and every pixel stays Blender-sourced. This is the boundary most
     likely to be approved.
  2. **Bone scaling on a Blender rig** for proportions (Bible 12: "verify deformation at extreme
     supported proportions").
  3. **Offline bpy generation** using Blender's own metaballs, Skin modifier or Geometry Nodes SDF
     grid nodes to make base bodies that an artist then finishes. Outputs are ours; Blender's GPL does
     not reach them.
  4. **Runtime metaball/marching-cubes skin** in our own GDScript or GDExtension code. Only with an
     explicit owner-approved boundary; it is closest to Spore's look but furthest from the Bible's
     pipeline. Treat as a research spike, not a plan.

### 2. Procedural animation and IK

- Godot 4.6 brought IK back as `IKModifier3D` with TwoBone, FABRIK, CCD, Jacobian and Spline solvers,
  on top of the `SkeletonModifier3D` stack (LookAt, SpringBone, BoneConstraint, angular velocity
  limiting). All are in our pinned 4.7.2 and MIT. This removes the need for any IK add-on.
- `SkeletonIK3D` is deprecated; don't build on it. Many Bone IK needs a custom engine build. GodotIK
  is superseded.
- The work that remains is ours: rig families, gait templates, foot placement, and the Hecker-style
  "describe motion against semantic targets, solve per creature" layer. Write it as a domain-free
  service (gait planning is pure maths and testable) with a thin scene adapter that sets IK targets.

### 3. Godot add-ons

- **Testing:** GUT and gdUnit4 are MIT and current for 4.7. We already have our own runner; keep it.
  Revisit gdUnit4 only if we need input simulation or scene runners.
- **AI:** LimboAI (MIT, behavior trees + state machines, debugger) is the strongest fit for Bible 13's
  explicit AI states once the ecosystem grows past M1. Beehave is lighter but the version
  information on its page is inconsistent. M1's few states can stay hand-written.
- **Camera:** Phantom Camera (MIT) is active and tracks 4.7.1, but is pre-1.0; our M1 camera is simple.
- **Terrain and scatter:** Terrain3D (MIT) for later land eras; ProtonScatter and Spatial Gardener
  (MIT) for plants and rocks. All three touch the Bible's "approved boundary" rule for runtime terrain
  and placement, so the boundary must be written before any of them is installed.
- **Physics:** Jolt is built into Godot and is the default for new projects since 4.6; the separate
  Godot Jolt extension is in maintenance mode. Our project does not set a physics engine, so it most
  likely runs Godot Physics today. Whether to switch is a project-setting decision, not a dependency.
- **Debug draw:** Debug Draw 3D (MIT) is handy for perception and IK debugging; dev builds only.
- **Dialogue:** Dialogue Manager (MIT) suits later social/tribal/civilization eras.
- **Saves:** no add-on recommended. Our `game/systems` persistence with schema versions and
  migrations is already the authority (save schema changes need approval).
- **Input and accessibility:** Godot's InputMap covers remapping; Godot 4.5+ has built-in screen
  reader support (experimental) through AccessKit. No add-on needed.

### 4. Blender pipeline helpers

- **glTF-Validator** (Apache-2.0, Khronos): run on each export in `tools/check.sh` or CI to catch
  broken GLBs before Godot import. Dev tool, never shipped. Best near-term value.
- **gltfpack / meshoptimizer** (MIT): Godot already uses meshoptimizer for import-time LODs, so try
  those first. If they fail the silhouette check, gltfpack `-si` can make candidate LODs, which then
  return to Blender for review and become part of the `.blend` source. Avoid its compressed/quantized
  output until Godot support is checked.
- **Blender glTF exporter** (Apache-2.0) is bundled; its exporter settings are already pinned via our
  bpy script.
- Blender add-ons from third parties are usually GPL: fine to use as authoring tools, never copy their
  code into `game/`.

### 5. Asset and audio sources

- CC0 sources verified: Poly Haven, ambientCG, Kenney. Freesound and OpenGameArt are mixed and
  per-file.
- Realistic use under the Bible: HDRIs for lighting tests, texture bases repainted toward our style,
  and placeholder or Foley audio. External 3D meshes are reference only, or need explicit approval and
  real Blender authorship.
- Every imported file should get a provenance line (source URL, license, author, date) in the asset
  record; CC-BY files also go in the credits.

### 6. Research worth reimplementing

- Spore's retargeting paper (Hecker et al., SIGGRAPH 2008) is the key public reference for animating
  user-built creatures. Cite it as design knowledge; write our own code.
- FABRIK (2011) explains the solver we would use through Godot.
- Leg stepping patterns from public tutorials are simple, well known and safe to reimplement.
- Metaball/marching cubes and B-Mesh are classic public algorithms; useful for offline Blender
  generation scripts.

## Top 5 recommendations

1. **Use Godot's built-in IK and SkeletonModifier3D stack (4.6+) for all procedural animation.**
   MIT, already in the pinned engine, no new dependency, and it covers TwoBone, FABRIK, CCD,
   LookAt and spring bones. Needs a 4.7.2 spike to confirm behaviour.
2. **Propose a "shape keys and bone scale on Blender-authored parts" runtime deformation boundary.**
   It gives Spore-like body variety while keeping every mesh Blender-sourced, and needs no library.
   Owner approval required (Bible 12, 15).
3. **Add Khronos glTF-Validator (Apache-2.0) as a dev-only CI check on exported GLBs.**
   Cheap, catches pipeline breakage early, and fits Bible 16 step 7. Needs owner approval as a
   tool dependency.
4. **Write our own gait/retargeting service from Hecker et al. 2008 and the leg-stepping pattern.**
   Pure maths in `game/domain` or `game/systems`, fully testable, and nothing copied.
5. **Shortlist LimboAI (MIT) for AI from M2 onward, and use CC0 sources (Poly Haven HDRIs, ambientCG
   textures, Freesound CC0) for lighting tests and placeholder audio.** LimboAI matches Bible 13's
   explicit states with a debugger; the CC0 sources need only provenance records.

## Reference only (copyleft)

Nothing below may be copied into Pangaea (code, shaders, data, art or audio). Studying how a feature
plays and writing our own design in our own words is fine.

- **Thrive** (GPL-3.0-or-later, Godot/C#). Already recorded in `docs/DECISIONS.md`. Ideas worth
  studying, by playing and reading public devblogs:
  - Auto-evo: background population simulation that decides which species thrive, relevant to
    Bible 13's aggregate updates for distant populations.
  - Cell editor flow: part placement, cost preview, symmetry, and how it explains why a part is
    invalid.
  - The move away from a hex grid for organelle placement (their "Devblog #3: A Farewell to
    Hexagons", https://www.revolutionarygamesstudio.com/devblog-3-farewell-hexagons/, not read in
    this pass).
  - Compound clouds and resource fields as readable food sources.
  - Their asset license was not stated in the files checked; treat all Thrive art and audio as
    copyleft.
- **Blender and most Blender add-ons** (GPL-2.0-or-later). Use freely as tools; their output is ours.
  Do not copy their source into the game.
- **OpenGameArt items under CC-BY-SA, OGA-BY with SA terms, or GPL**, and **Freesound items under
  CC-BY-NC or Sampling+**: do not use.
- **Spore** (proprietary, EA): design benchmark only. No files, formats or assets (owner decision
  2026-10-22).

## Open questions for the owner

- Approve a runtime deformation boundary (recommendation 2) before any procedural mesh work.
- Approve glTF-Validator as a dev-only tool dependency.
- Decide whether to switch the project to the built-in Jolt physics module, and when.
- Confirm that CC0 textures, HDRIs and audio are acceptable inputs if provenance is recorded.
