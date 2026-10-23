"""The endless world's new threat bodies (docs/endless-cell-plan.md B.7), in finished art: size 2's
elder rammer and Lurker (S2), and size 3 and 4's Warden, elder Warden, Deep lurker and stinger veil (S3).

Both are drop-ins on the step 3 body contract (tools/blender/make_m1_threats.py): built at size 1 on
PartPlacement's frame, with the same pose nodes and material names as the body they grow from, so
the creature view animates them as it does that body.
- creature_elder_rammer_body: the rammer's body, older. Bulkier and darker, with a weathered ochre hide,
  deep rust bands and a taller seven-point crest. Nodes Body, Eye_L/R (Pupil, Lid), Hood.
- creature_lurker_body: built on the ambush hunter's body. Flatter and longer-backed, in violet-grey
  reef tones with three low ridges down the back, and pale eyes set wide on the flanks for its wide
  sight. Nodes Body, Eye_L/R (Pupil), Brow.
- creature_warden_body: on the rammer's body. Lower and broader-shouldered, a cool slate-blue hide with
  three cream bands and a short, many-pointed crest: the meadow keeper. Nodes as the rammer.
- creature_elder_warden_body: the Warden grown old: deeper slate, rust-cream bands, a tall crest.
- creature_deep_lurker_body: on the ambush hunter's body. A long, low navy body with pale cyan
  glowing eyes set forward along its lunge and faint glowing spots down the back. Nodes as the ambush hunter.
- creature_veil_body: on the ambush hunter's body. A tall lilac bell with radial canals and a pale rim,
  small dark eyes under a soft brow; the engine draws its stinging threads. Nodes as the ambush hunter.

Each is built by make_m1_production.py's own threat pass (finer body for the normal map, reduction
within the colour and frame contracts, one baked texture set) with the base body's constants swapped
for the variant's. The body's vertex colours need an external engine material, as the base bodies:
assets/export/M_ElderRammerBody.tres and M_LurkerBody.tres, mapped in each .glb.import by --import.

Run: python tools/blender/make_endless_threats.py [--only <id>[,<id>...]]
     python tools/blender/make_endless_threats.py --import   (after Godot has imported the GLBs once)
"""
import argparse
import math
import os
import re
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import blockout_common as bc  # noqa: E402  (imports bpy first)
import make_m1_threats as mt  # noqa: E402
import make_m1_production as mp  # noqa: E402

GENERATOR = "tools/blender/make_endless_threats.py"
REVIEW_STATE = mp.REVIEW_STATE
PROVENANCE = ("Authored procedurally in Blender by tools/blender/make_endless_threats.py on the step 3 body code "
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


def _with(overrides, top=None, color=None):
    """Runs a build with make_m1_threats' constants (and optionally its ambush top and colour
    functions) swapped."""
    swaps = dict(overrides)
    if top is not None:
        swaps["_ambush_top"] = top
    if color is not None:
        swaps["_ambush_color"] = color

    def wrap(builder):
        def run():
            keep = {k: getattr(mt, k) for k in swaps}
            for k, v in swaps.items():
                setattr(mt, k, v)
            try:
                return builder()
            finally:
                for k, v in keep.items():
                    setattr(mt, k, v)
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


WARDEN = {
    "RAMMER_TOP": 0.33, "RAMMER_BOTTOM": 0.26, "RAMMER_ROUND": (0.8, 0.85),
    "RAMMER_SAND": "#7C8FB4",            # cool slate blue
    "RAMMER_BAND": "#1E2A47",
    "RAMMER_LID": "#5F7096",
    "RAMMER_BANDS": [(0.2, 0.035), (0.0, 0.04), (-0.2, 0.035)],
    "CREST_POINTS": 9, "CREST_TIP": 0.12, "CREST_VALLEY": 0.05, "CREST_SPAN": (0.2, -0.34),
    "RAMMER_LID_FROWN_DEG": 14.0,
}

ELDER_WARDEN = dict(WARDEN, **{
    "RAMMER_TOP": 0.37,
    "RAMMER_SAND": "#56688F",            # deeper slate
    "RAMMER_BAND": "#3A1E1C",            # old rust bands
    "RAMMER_LID": "#43517A",
    "RAMMER_BANDS": [(0.2, 0.05), (0.0, 0.055), (-0.2, 0.05)],
    "CREST_POINTS": 9, "CREST_TIP": 0.2, "CREST_VALLEY": 0.07,
    "RAMMER_LID_FROWN_DEG": 26.0,
})

DEEP_LURKER = {
    "AMBUSH_TOP": 0.075, "AMBUSH_HEAD": 0.03, "AMBUSH_BOTTOM": 0.075,
    "AMBUSH_EYE": (0.12, 0.33, 0.07),    # set forward, along its lunge
    "AMBUSH_BACK": "#1F2E52",            # deep navy, never black
    "AMBUSH_MOTTLE": "#141D36",
    "AMBUSH_FLECK": "#5F86B8",
    "AMBUSH_BROW": "#18223F",
    "MINERAL_AMBER": "#8FE0EC",          # pale cyan glow
    "AMBUSH_EYE_GLOW": 0.7,
}

VEIL = {
    "AMBUSH_TOP": 0.34, "AMBUSH_HEAD": 0.0, "AMBUSH_TAIL_THIN": 0.0, "AMBUSH_BOTTOM": 0.06,
    "AMBUSH_ROUND": (0.9, 0.6), "AMBUSH_MAX_HEIGHT_SHARE": 0.5,
    "AMBUSH_EYE": (0.15, 0.3, 0.05),
    "AMBUSH_BROW": "#6D5A8C",
    "MINERAL_AMBER": "#2E2747",          # small dark eyes
    "AMBUSH_EYE_GLOW": 0.0,
}
VEIL_BELL = "#B7A3D9"
VEIL_CANAL = "#7E68A8"
VEIL_RIM = "#E6DDF2"
VEIL_CANALS = 10


def _veil_top(x, y):
    """A bell: a high dome with soft radial canals sunk into it."""
    r = min(1.0, math.hypot(x / mt.FRAME_RX, y / mt.FRAME_RZ))
    a = math.atan2(x, y)
    dome = mt.AMBUSH_TOP * (1.0 - r * r) ** 0.6
    canal = 0.012 * (0.5 + 0.5 * math.cos(VEIL_CANALS * a)) * bc.smoothstep((r - 0.15) / 0.3)
    return dome - canal


def _veil_color(p):
    bell, canal, rim, belly = (mt.linear(c) for c in (VEIL_BELL, VEIL_CANAL, VEIL_RIM, mt.CREAM))
    r = min(1.0, math.hypot(p.x / mt.FRAME_RX, p.y / mt.FRAME_RZ))
    a = math.atan2(p.x, p.y)
    stripe = bc.smoothstep((math.cos(VEIL_CANALS * a) - 0.55) / 0.35) * bc.smoothstep((r - 0.15) / 0.3)
    color = mt._mix(bell, canal, 0.75 * stripe)
    color = mt._mix(color, rim, 0.8 * bc.smoothstep((r - 0.8) / 0.15))
    if p.z < 0.0:
        color = mt._mix(color, belly, 0.6)
    return color


def _variant(builder, overrides, purpose, tres, base, **funcs):
    def build():
        fields = _with(overrides, **funcs)(builder)()
        fields.update({"purpose": purpose, "dependencies": [f"assets/export/{tres}.tres"], "revision": 1, "variant_of": base})
        return fields
    return build


build_warden = _variant(
    mp.build_creature_rammer_body, WARDEN,
    "S3 Warden body (role: territorial, size 3's keeper of wide meadows): lower and broader than the rammer, a cool slate-blue hide with three dark bands and a short, many-pointed crest. Body only; its parts come from the part GLBs.",
    "M_WardenBody", "creature_rammer_body")
build_elder_warden = _variant(
    mp.build_creature_rammer_body, ELDER_WARDEN,
    "S3 elder Warden body (role: territorial, size 4's guard that follows the bloom): the Warden grown old, deeper slate with rust bands, heavy frowning lids and a tall nine-point crest. Body only; its parts come from the part GLBs.",
    "M_ElderWardenBody", "creature_rammer_body")
build_deep_lurker = _variant(
    mp.build_creature_ambush_body, DEEP_LURKER,
    "S3 Deep lurker body (role: ambush, size 4's channel lunger): a long, low deep-navy body with pale flecks and pale cyan eyes set forward along its lunge, under a heavy brow. Body only; its parts come from the part GLBs.",
    "M_DeepLurkerBody", "creature_ambush_body")
build_veil = _variant(
    mp.build_creature_ambush_body, VEIL,
    "S3 stinger veil body (role: passive hazard, size 3): a tall lilac bell with ten darker radial canals and a pale rim, small dark eyes under a soft brow. The engine draws its stinging threads. Built on the ambush hunter's body code, so its nodes and material names are the ambush hunter's.",
    "M_VeilBody", "creature_ambush_body", top=_veil_top, color=_veil_color)


ASSETS = {
    "creature_elder_rammer_body": (build_elder_rammer, 4000, "M_RammerBody", "M_ElderRammerBody", "Rammer"),
    "creature_lurker_body": (build_lurker, 4000, "M_AmbushBody", "M_LurkerBody", "AmbushHunter"),
    "creature_warden_body": (build_warden, 4000, "M_RammerBody", "M_WardenBody", "Rammer"),
    "creature_elder_warden_body": (build_elder_warden, 4000, "M_RammerBody", "M_ElderWardenBody", "Rammer"),
    "creature_deep_lurker_body": (build_deep_lurker, 4000, "M_AmbushBody", "M_DeepLurkerBody", "AmbushHunter"),
    "creature_veil_body": (build_veil, 4000, "M_AmbushBody", "M_VeilBody", "AmbushHunter"),
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
