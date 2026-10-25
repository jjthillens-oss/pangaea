"""Twenty more creature parts (PROPOSED; owner request "more-parts", docs/art/creature_parts_more.md): beaks,
trunks, more mouths and eyes, webbed and padded feet, antlers, tails of four kinds, shells, a mane ridge and a
feather crest, so players can build many more animal types.

Same convention as tools/blender/make_creature_parts.py (docs/art/creature_art_contract.md, section 1), whose
helpers this script imports and never edits:
- Blender +Z (Godot +Y) is the skin normal at the anchor, Blender +Y (Godot -Z) points toward the head.
- The pivot is where the part meets the skin; geometry below it, down to sink_depth, is the root.
  Ground parts (feet) instead stand on the pivot: +Z is body up at rest, the sole on z = 0, the ankle top at about
  z = 0.09 (anchor_resolver.gd GROUND_ANKLE_M).
- Mouths and eyes are authored like the existing ones (their outward axis along Blender +Z, the upper side on +Y),
  so every mouth and every eye is placed by the same forward_cone frame.
- Authored at the part's nominal size for a body about 1 m long (scale 1000 per mille).
- Up to four shape keys H1_..H4_ are the handles, 0 to 1000 per mille; the runtime sets them as blend shapes.
- One root mesh named after the part type, no bones; chiral parts ship the right-hand (+X) side only.
- record["part_rules"] holds the PartRules values; tools/make_part_rules.py copies them into
  game/data/creature/part_rules.json, which is how a part reaches the editor's palette (data only).

Each part is finished like the others: procedural greyscale detail baked to one texture set (albedo detail with AO,
ORM, normal), each material keeping its name and flat colour, and paint_mix saying how much of the creature's paint
replaces that colour. Each record carries review_notes: the finish-hunyuan-assets Gates 1 to 4 as pass, needs
revision or unverified, with the observation behind it (tools/blender/render_more_parts_gates.py renders Gates 1-3,
tools/godot/more_parts_shots.gd Gate 4).

Helpers that make_creature_parts.py defines twice (_smooth, _pad_material, _fur_material) are copied here under an
_mp prefix rather than called through the module, so a rename there cannot change these parts.

Run: python3 tools/blender/make_more_creature_parts.py [--only <id>[,<id>...]]   (bpy 5.2.2)
Then godot --headless --path . --import, and python3 tools/make_part_rules.py.
"""
import argparse
import math
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import blockout_common as bc  # noqa: E402  (imports bpy first)
import make_creature_parts as cp  # noqa: E402,F401  (the shared part helpers: _tube, _bake, _shape_keys, ...)
import make_m1_production as mp  # noqa: E402
import surfacing as sf  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402,F401

GENERATOR = "tools/blender/make_more_creature_parts.py"
REVIEW_STATE = mp.REVIEW_STATE
PROVENANCE = ("Authored procedurally in Blender by tools/blender/make_more_creature_parts.py, with helpers from "
              "tools/blender/make_creature_parts.py; no external or generated meshes. Textures baked in Blender from "
              "procedural shaders.")

# What each part does in play (PROPOSED), chosen from the roles the creature code already reads
# (game/domain/creature/creature_stats.gd; Bible section 12, Anatomy and evolution model):
# - mouth: "mouth and feeding apparatus" (bite and reach). The trunks are feeding apparatus with reach.
# - eye: "eyes and sensory organs" (sight).
# - foot: "legs and feet" (no stat today).
# - weapon: the antlers and the stinger strike; the codebase's stand-in for "armor and spines" (attack).
# - detail: display parts (charm), and the parts whose own effect has no role yet: the shells (there is no
#   defensive role, and weapon would add attack), the paddle tail (no swim role) and the curling tail (no grasp
#   effect; it carries the grasper capability instead). The per-kind effects are proposed in a GitHub issue.
ROLE = {
    "beak_hooked": "mouth", "beak_long": "mouth", "trunk": "mouth", "trunk_short": "mouth",
    "mouth_sucker": "mouth", "mouth_fangs": "mouth",
    "eye_turret": "eye", "eye_lashed": "eye",
    "foot_otter": "foot", "foot_pillar": "foot",
    "antler_branched": "weapon", "antler_palmate": "weapon", "tail_stinger": "weapon",
    "tail_feather": "detail", "tail_paddle": "detail", "tail_curl": "detail",
    "shell_dome": "detail", "shell_spiral": "detail", "mane_ridge": "detail", "crest_feather": "detail",
}

# part_rules "capabilities" (optional; the hand records set the precedent and no game code reads it yet):
# Bible section 12, grasping structures.
CAPABILITIES = {"trunk": ["grasper"], "tail_curl": ["grasper"]}

GATES = ("gate1_shape", "gate2_materials", "gate3_neutral_light", "gate4_godot")
# asset id -> {gate: "pass: ..." | "needs revision: ..." | "unverified: ..."}, filled in as each part is reviewed.
REVIEW = {}


def _rules(part_type, footprint, sink, orientation, hosts, turn, tilt, centerline="allowed", chiral=False):
    """The PartRules block, in the same keys and order as make_creature_parts._rules, from this script's ROLE."""
    rules = {"type": part_type, "footprint_radius_m": footprint, "sink_depth_m": sink, "chiral": chiral,
             "orientation": orientation, "turn_limit_deg": turn, "tilt_limit_deg": tilt,
             "centerline": centerline, "hosts": hosts, "role": ROLE[part_type]}
    if part_type in CAPABILITIES:
        rules["capabilities"] = list(CAPABILITIES[part_type])
    return rules


def _review_notes(asset_id):
    notes = {gate: "unverified: not reviewed yet" for gate in GATES}
    notes.update(REVIEW.get(asset_id, {}))
    return notes


# --- Helpers copied from make_creature_parts.py (defined there twice; see the module docstring) ------------------


def _mp_smooth(x, a, b):
    """Smoothstep of x from a to b."""
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


def _mp_pad_material(name, rough=0.4):
    """A soft pad or nose leather: a fine tight pebble, smoother than the skin around it."""
    sh = sf.Shader(name)
    pebble = sh.remap(sh.voronoi(900.0, 0.9), 0.3, 0.05)
    sh.bump(sh.math("SUBTRACT", 0.0, pebble), 0.18, 0.0003)
    return sh.out(cp._grey(sh, sh.math("SUBTRACT", 1.0, sh.math("MULTIPLY", pebble, 0.2)), 0.8), rough)


def _mp_fur_material(name, lo=0.55, along=(7.0, 7.0, 0.35), rough=0.88):
    """Matte fur: fine streaks stretched along the strands (the low-frequency axis of `along`), clumped breakup."""
    sh = sf.Shader(name)
    strands = sh.noise(260.0, 2.0, vector=mp._stretched(sh, along))
    clumps = sh.remap(sh.noise(45.0, 2.0), 0.35, 0.65)
    sh.bump(strands, 0.35, 0.0007)
    fac = sh.math("ADD", sh.math("MULTIPLY", sh.remap(strands, 0.3, 0.7), 0.6), sh.math("MULTIPLY", clumps, 0.4))
    return sh.out(cp._grey(sh, fac, lo), rough)


# --- Parts --------------------------------------------------------------------------------------------------------
# Builders return {purpose, category: "part", part_type, convention, part_rules, paint_mix, revision, **baked}, as
# make_creature_parts.py's do. They are added batch by batch (docs/art/creature_parts_more.md).


ASSETS = {
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    parser = argparse.ArgumentParser(description="Build the more-parts creature parts.")
    parser.add_argument("--only", default="", help="comma-separated asset ids (default: all)")
    args = parser.parse_args(argv)
    ids = [i for i in args.only.split(",") if i] or list(ASSETS)
    unknown = [i for i in ids if i not in ASSETS]
    if unknown:
        parser.error(f"unknown asset id(s): {', '.join(unknown)}; known: {', '.join(ASSETS) or '(none yet)'}")
    for asset_id in ids:
        builder, budget = ASSETS[asset_id]
        bc.reset_scene()
        fields = builder()
        fields["review_notes"] = _review_notes(asset_id)
        record = bc.export(asset_id, budget, fields, review_state=REVIEW_STATE, generator=GENERATOR, provenance=PROVENANCE)
        dims = record["dimensions_m"]
        print(f"{asset_id}: {record['triangles']} triangles, {dims['x']} x {dims['y_forward']} x {dims['z_up']} m")


if __name__ == "__main__":
    main()
    sys.stdout.flush()
