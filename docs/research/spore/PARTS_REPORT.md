# Parts report: the art team's parts on generated creatures

Status: PROTOTYPE results, 2026-10-23. Built under the owner's go ahead to continue overnight. The code is in
`prototypes/creature-lab/`. Nothing in `game/` changed. Not Windows-verified.

Inputs: the anchor design in `workstreams/creature_editor.md` §3.3–3.6, the art contract
(`docs/art/creature_art_contract.md`), and the art team's first five parts (beak, eye, fin, foot, horn) with their
records. No Spore material.

## 1. Result

Generated creatures now wear the art team's Blender parts and skin shader, standing still and walking:

- **Anchors (body description version 3).** A part is stored relative to its host, not as a position:
  - the host is the spine, a limb, or a limb's end;
  - where along the host, and the angle around it;
  - at the spine's ends, how far it leans off the axis;
  - turn, tilt, roll, scale, the shape-key handles, and a mirror flag.

  All are integers, as with the rest of the description.
- **On the skin by construction.** The resolver finds the skin along the anchor's direction by bisection on the
  body field. Every placed part on the test bodies sits within 0.001% of body length of the skin. When the head is
  thickened by half, the eyes move out with it and stay on the skin.
- **Mirrored twins** are the exact reflection across the middle plane, so chiral horns curl outward on both sides.
- **Orientation rules** from the records:
  - *normal* parts stand on the skin normal and face the head;
  - *forward-cone* parts (eyes, beaks) look ahead, turned at most 45° towards the skin normal;
  - *ground* parts (feet) stay level and face the heading. A walking leg stands on its foot's sole (the ankle top
    meets the limb tip, per the foot record).
- **Rules from the art records** (`assets/records/cpart_*.json`, `part_rules`). These are refused with a reason:
  - a part on a host its type does not allow;
  - a beak off the middle line;
  - a chiral horn on the middle line;
  - a turn past its limit or a scale outside 0.5–2×;
  - a twin on a limb that has no mirror copy;
  - a missing host.
- **Rig.** Each part rides its host bone through a `BoneAttachment3D`. Handles set the parts' shape keys. The body
  uses the art team's `creature_skin.gdshader` with `body_length_m` from the rig.

Tests: `tests/run_stage1_tests.gd` adds 16 part checks. All suites pass. The walker measurements are unchanged:
40 runs, at most 0.4% stance slip, all finite.

## 2. Limits and next steps (PROPOSED)

- The prototype loads the GLBs and the shader at runtime from the main project, because it is a separate Godot
  project. In the game they would be imported resources.
- Chiral twins use a mirrored transform (determinant −1). The contract asks for a bake-time mirrored mesh, which
  comes with the game version.
- Parts hosted on other parts (an eye on a stalk) and part-to-part overlap checks are not built.
- Next: an editor scene to place and drag parts and vertebrae, using the GPU rebuild.
