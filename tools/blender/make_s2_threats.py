"""The endless world's size-2 threat bodies (S2, docs/endless-cell-plan.md B.7): the elder rammer and
the Lurker, in finished art.

Both are drop-ins on the step 3 body contract (tools/blender/make_m1_threats.py): built at size 1 on
PartPlacement's frame, with the same pose nodes and material names as the body they grow from, so
the creature view animates them as it does that body.
- creature_elder_rammer_body: the rammer's body, older. Bulkier and darker, with a weathered ochre hide,
  deep rust bands and a taller seven-point crest. Nodes Body, Eye_L/R (Pupil, Lid), Hood.
- creature_lurker_body: built on the ambush hunter's body. Flatter and longer-backed, in violet-grey
  reef tones with three low ridges down the back, and pale eyes set wide on the flanks for its wide
  sight. Nodes Body, Eye_L/R (Pupil), Brow.

Each is built by make_m1_production.py's own threat pass (finer body for the normal map, reduction
within the colour and frame contracts, one baked texture set) with the base body's constants swapped
for the variant's. The body's vertex colours need an external engine material, as the base bodies:
assets/export/M_ElderRammerBody.tres and M_LurkerBody.tres, mapped in each .glb.import by --import.

Run: python tools/blender/make_s2_threats.py [--only <id>[,<id>...]]
     python tools/blender/make_s2_threats.py --import   (after Godot has imported the GLBs once)
"""
import argparse
import os
import re
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import blockout_common as bc  # noqa: E402  (imports bpy first)
import make_m1_threats as mt  # noqa: E402
import make_m1_production as mp  # noqa: E402

GENERATOR = "tools/blender/make_s2_threats.py"
REVIEW_STATE = mp.REVIEW_STATE
PROVENANCE = ("Authored procedurally in Blender by tools/blender/make_s2_threats.py on the step 3 body code "
              "(make_m1_threats.py, make_m1_production.py); no external or generated meshes. Textures baked in "
              "Blender from procedural shaders.")

ELDER_RAMMER = {
    "RAMMER_TOP": 0.44, "RAMMER_BOTTOM": 0.32,
    "RAMMER_SAND": "#A2845A",            # weathered ochre, darker than the rammer's pale sand
    "RAMMER_BAND": "#3F1F1B",            # deep rust bands
    "RAMMER_LID": "#7E6442",
    "RAMMER_BANDS": [(0.16, 0.055), (-0.06, 0.065), (-0.28, 0.055)],
    "CREST_POINTS": 7, "CREST_TIP": 0.22, "CREST_VALLEY": 0.07, "CREST_SPAN": (0.14, -0.32),
    "RAMMER_LID_FROWN_DEG": 28.0,
}

LURKER = {
    "AMBUSH_TOP": 0.085, "AMBUSH_HEAD": 0.025, "AMBUSH_BOTTOM": 0.08,
    "AMBUSH_EYE": (0.27, 0.2, 0.08),     # wide set on the flanks: wide sight
    "AMBUSH_BACK": "#4A4262",            # violet-grey reef tones
    "AMBUSH_MOTTLE": "#262338",
    "AMBUSH_FLECK": "#8577A6",
    "AMBUSH_BROW": "#332D47",
    "MINERAL_AMBER": "#C9D3F2",          # pale, cold eyes (they glow as the ambush hunter's do)
}
LURKER_RIDGES = [(-0.13, 0.016), (0.0, 0.022), (0.13, 0.016)]   # (x, height): low ridges down the back


def _lurker_top(x, y):
    h = _base_ambush_top(x, y)
    along = bc.smoothstep((0.32 - y) / 0.2) * bc.smoothstep((y + 0.45) / 0.2)
    for rx, rh in LURKER_RIDGES:
        h += rh * along * mt.gauss((x - rx) ** 2, 0.0012)
    return h


_base_ambush_top = mt._ambush_top


def _with(overrides, top=None):
    """Runs a build with make_m1_threats' constants (and optionally its ambush top) swapped."""
    def wrap(builder):
        def run():
            keep = {k: getattr(mt, k) for k in overrides}
            keep_top = mt._ambush_top
            for k, v in overrides.items():
                setattr(mt, k, v)
            if top is not None:
                mt._ambush_top = top
            try:
                return builder()
            finally:
                for k, v in keep.items():
                    setattr(mt, k, v)
                mt._ambush_top = keep_top
        return run
    return wrap


def build_elder_rammer():
    fields = _with(ELDER_RAMMER)(mp.build_creature_rammer_body)()
    fields.update({
        "purpose": "S2 elder rammer body (role: territorial, size 2's guard of two feast zones): the rammer grown old, bulkier and darker, a weathered ochre hide with three deep rust bands, heavier frowning lids and a taller seven-point crest. Body only; its parts come from the part GLBs.",
        "dependencies": ["assets/export/M_ElderRammerBody.tres"],
        "revision": 1,
        "variant_of": "creature_rammer_body",
    })
    return fields


def build_lurker():
    fields = _with(LURKER, top=_lurker_top)(mp.build_creature_ambush_body)()
    fields.update({
        "purpose": "S2 Lurker body (role: lurker, size 2's two-lair reef threat): a flat, long-backed reef dweller in violet-grey with dark mottles, three low ridges down its back and pale cold eyes set wide on its flanks for its wide sight, under a heavy brow. Body only; its parts come from the part GLBs.",
        "dependencies": ["assets/export/M_LurkerBody.tres"],
        "revision": 1,
        "variant_of": "creature_ambush_body",
    })
    return fields


ASSETS = {
    "creature_elder_rammer_body": (build_elder_rammer, 4000, "M_RammerBody", "M_ElderRammerBody", "Rammer"),
    "creature_lurker_body": (build_lurker, 4000, "M_AmbushBody", "M_LurkerBody", "AmbushHunter"),
}

TRES = """[gd_resource type="StandardMaterial3D" load_steps=4 format=3]

; The {what} body's material (assets/records/{id}.json). As the base body's material: its colour is
; the mesh's vertex colours (sRGB-encoded), times the GLB's baked greyscale detail, with the baked
; ORM's roughness and normal map. {id}.glb.import points the imported {mat} here.

[ext_resource type="Texture2D" path="res://assets/export/{id}_T_{tex}_Albedo.png" id="1_albedo"]
[ext_resource type="Texture2D" path="res://assets/export/{id}_T_{tex}_ORM.png" id="2_orm"]
[ext_resource type="Texture2D" path="res://assets/export/{id}_T_{tex}_Normal.png" id="3_normal"]

[resource]
resource_name = "{mat}"
vertex_color_use_as_albedo = true
vertex_color_is_srgb = true
albedo_texture = ExtResource("1_albedo")
roughness_texture = ExtResource("2_orm")
roughness_texture_channel = 1
normal_enabled = true
normal_texture = ExtResource("3_normal")
"""


def map_materials():
    """Writes each body's .tres and points its .glb.import's body material at it."""
    for asset_id, (_, _, mat, tres, tex) in ASSETS.items():
        what = asset_id[len("creature_"):-len("_body")].replace("_", " ")
        with open(os.path.join(bc.ROOT, "assets", "export", f"{tres}.tres"), "w") as f:
            f.write(TRES.format(what=what, id=asset_id, tex=tex, mat=mat))
        path = os.path.join(bc.ROOT, "assets", "export", f"{asset_id}.glb.import")
        with open(path) as f:
            text = f.read()
        mapping = ('_subresources={{\n"materials": {{\n"{mat}": {{\n"use_external/enabled": true,\n'
                   '"use_external/fallback_path": "res://assets/export/{tres}.tres",\n'
                   '"use_external/path": "res://assets/export/{tres}.tres"\n}}\n}}\n}}').format(mat=mat, tres=tres)
        text = re.sub(r"_subresources=\{.*?\n\}(?=\n|$)", mapping, text, flags=re.S) if "_subresources={\n" in text \
            else text.replace("_subresources={}", mapping)
        with open(path, "w") as f:
            f.write(text)
        print("mapped", mat, "->", tres, "in", os.path.basename(path))


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    parser = argparse.ArgumentParser(description="Build the S2 threat bodies.")
    parser.add_argument("--only", default="", help="comma-separated asset ids (default: all)")
    parser.add_argument("--import", dest="map_only", action="store_true", help="only write the .tres files and .glb.import mappings")
    args = parser.parse_args(argv)
    if args.map_only:
        map_materials()
        return
    ids = [i for i in args.only.split(",") if i] or list(ASSETS)
    unknown = [i for i in ids if i not in ASSETS]
    if unknown:
        parser.error(f"unknown asset id(s): {', '.join(unknown)}; known: {', '.join(ASSETS)}")
    for asset_id in ids:
        builder, budget = ASSETS[asset_id][:2]
        bc.reset_scene()
        fields = builder()
        record = bc.export(asset_id, budget, fields, review_state=REVIEW_STATE, generator=GENERATOR, provenance=PROVENANCE)
        dims = record["dimensions_m"]
        print(f"{asset_id}: {record['triangles']} triangles, {dims['x']} x {dims['y_forward']} x {dims['z_up']} m")


if __name__ == "__main__":
    main()
    sys.stdout.flush()
